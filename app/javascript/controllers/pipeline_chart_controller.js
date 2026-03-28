import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"

// ─────────────────────────────────────────────────────────────────────
// Pipeline Chart Controller
//
// Architecture: bricks are grouped by goal into <g> elements so that
// hover dimming is a single opacity change per group (not per brick).
// All hover transitions use CSS (via classes) for GPU-accelerated,
// jitter-free animation.
// ─────────────────────────────────────────────────────────────────────

export default class extends Controller {
  static values = {
    url: String,
    compact: { type: Boolean, default: false }
  }

  static BLOCK_COLORS = [
    "#ef4444", // red
    "#f97316", // orange
    "#eab308", // yellow
    "#22c55e", // green
    "#06b6d4", // cyan
    "#3b82f6", // blue
    "#8b5cf6", // violet
    "#ec4899", // pink
    "#14b8a6", // teal
    "#f43f5e", // rose
  ]

  connect() {
    this.margin = this.compactValue
      ? { top: 20, right: 20, bottom: 30, left: 44 }
      : { top: 24, right: 24, bottom: 36, left: 50 }
    this.minWidth = 400

    // Inject CSS for hover transitions (once per page)
    if (!document.getElementById("pipeline-chart-styles")) {
      const style = document.createElement("style")
      style.id = "pipeline-chart-styles"
      style.textContent = `
        .goal-group {
          transition: opacity 0.15s ease-out;
        }
        .pipeline-svg[data-hovering] .goal-group {
          opacity: 0.2;
        }
        .pipeline-svg[data-hovering] .goal-group[data-active] {
          opacity: 1;
        }
        .pipeline-svg[data-hovering] .goal-group[data-active] .brick {
          stroke: rgba(255,255,255,0.6);
          stroke-width: 1.5;
          vector-effect: non-scaling-stroke;
        }
        .label-group {
          transition: opacity 0.15s ease-out;
        }
        .pipeline-svg[data-hovering] .label-group {
          opacity: 0.15;
        }
        .pipeline-svg[data-hovering] .label-group[data-active] {
          opacity: 1;
        }
        .pipeline-svg { cursor: grab; }
        .pipeline-svg:active { cursor: grabbing; }
        .pipeline-svg[data-hovering] { cursor: pointer; }
      `
      document.head.appendChild(style)
    }

    this.loadData()

    this.resizeHandler = this.debounce(() => this.render(), 250)
    window.addEventListener("resize", this.resizeHandler)

    this.refreshHandler = () => this.loadData()
    document.addEventListener("pipeline:refresh", this.refreshHandler)
  }

  disconnect() {
    window.removeEventListener("resize", this.resizeHandler)
    document.removeEventListener("pipeline:refresh", this.refreshHandler)
  }

  async loadData() {
    try {
      const response = await fetch(this.urlValue, {
        headers: {
          "Accept": "application/json",
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin"
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const text = await response.text()
      this.chartData = JSON.parse(text)
      this.includesWeekends = this.chartData.includes_weekends !== false
    } catch (error) {
      console.error("Pipeline chart fetch error:", error)
      this.element.innerHTML = `
        <div class="flex items-center justify-center h-48 text-gray-500">
          <p>Unable to load pipeline: ${error.message}</p>
        </div>
      `
      return
    }

    try {
      this.render()
    } catch (error) {
      console.error("Pipeline chart render error:", error)
      this.element.innerHTML = `
        <div class="flex items-center justify-center h-48 text-red-500">
          <p>Error rendering pipeline: ${error.message}</p>
        </div>
      `
    }
  }

  // ── Data ──────────────────────────────────────────────────────────

  computeBricks(goals) {
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const todayTime = today.getTime()
    const dayMs = 86400000

    const earliest = d3.min(goals, g => g.startDate)
    const latest = d3.max(goals, g => g.endDate)

    const getActualMinutes = (goal, dateStr) => {
      if (!goal.actual_minutes_by_date) return 0
      return goal.actual_minutes_by_date[dateStr] || 0
    }

    const bricks = []
    let maxY = 0
    let day = new Date(earliest)

    while (day < latest) {
      const dayTime = day.getTime()
      const nextDay = new Date(dayTime + dayMs)
      const isWeekend = day.getDay() === 0 || day.getDay() === 6
      const isPast = dayTime < todayTime
      const isToday = dayTime === todayTime
      const dateStr = day.toISOString().split('T')[0]

      const active = goals.filter(g => {
        if (g.startDate.getTime() > dayTime || g.endDate.getTime() <= dayTime) return false
        if (isWeekend && !this.includesWeekends) return false
        return true
      })

      let yOffset = 0
      active.forEach(g => {
        let minutes
        let todayProgress = 0
        if (isPast) {
          minutes = getActualMinutes(g, dateStr)
        } else if (isToday) {
          const quotaFraction = g.today_quota_progress || 0
          minutes = g.minutes_per_day
          todayProgress = quotaFraction * minutes
        } else {
          minutes = g.minutes_per_day
        }

        if (minutes > 0) {
          bricks.push({
            key: `${g.id}-${dateStr}`,
            goalId: g.id,
            goalIndex: g._index,
            date: new Date(day),
            nextDate: new Date(nextDay),
            dateStr,
            yOffset,
            minutes,
            isPast,
            isToday,
            todayProgress,
            color: g.color,
            isQueued: g._isQueued,
            isUnowned: g._isUnowned
          })
          yOffset += minutes
        }
      })

      maxY = Math.max(maxY, yOffset)
      day = nextDay
    }

    goals.forEach(g => { maxY = Math.max(maxY, g.minutes_per_day) })

    return { bricks, maxY }
  }

  computeLabels(bricks, goals) {
    const labels = []
    goals.forEach(goal => {
      const goalBricks = bricks
        .filter(b => b.goalId === goal.id)
        .sort((a, b) => a.date - b.date)
      if (!goalBricks.length) return

      const runs = []
      let currentRun = [goalBricks[0]]
      for (let i = 1; i < goalBricks.length; i++) {
        if (goalBricks[i].date.getTime() === currentRun[currentRun.length - 1].nextDate.getTime()) {
          currentRun.push(goalBricks[i])
        } else {
          runs.push(currentRun)
          currentRun = [goalBricks[i]]
        }
      }
      runs.push(currentRun)

      let widestRun = null
      let widestWidth = 0
      runs.forEach(run => {
        const w = this.xScale(run[run.length - 1].nextDate) - this.xScale(run[0].date)
        if (w > widestWidth) {
          widestRun = run
          widestWidth = w
        }
      })

      if (!widestRun) return

      const avgYOffset = d3.mean(widestRun, d => d.yOffset)
      const avgMinutes = d3.mean(widestRun, d => d.minutes)
      const labelHeight = this.yScale(avgYOffset) - this.yScale(avgYOffset + avgMinutes)

      labels.push({
        goalId: goal.id,
        goalIndex: goal._index,
        x: this.xScale(widestRun[0].date) + 8,
        xEnd: this.xScale(widestRun[widestRun.length - 1].nextDate) - 8,
        y: this.yScale(avgYOffset + avgMinutes) + labelHeight / 2,
        width: widestWidth,
        height: labelHeight,
        title: goal.title,
        minutesPerDay: goal.minutes_per_day,
        usesActualData: goal.uses_actual_data
      })
    })
    return labels
  }

  // ── Rendering ─────────────────────────────────────────────────────

  render() {
    if (!this.chartData || !this.chartData.goals.length) {
      this.element.innerHTML = `
        <div class="flex flex-col items-center justify-center h-48 text-gray-500">
          <svg class="w-10 h-10 text-gray-300 mb-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9 17V7m0 10a2 2 0 01-2 2H5a2 2 0 01-2-2V7a2 2 0 012-2h2a2 2 0 012 2m0 10a2 2 0 002 2h2a2 2 0 002-2M9 7a2 2 0 012-2h2a2 2 0 012 2m0 10V7m0 10a2 2 0 002 2h2a2 2 0 002-2V7a2 2 0 00-2-2h-2a2 2 0 00-2 2"/>
          </svg>
          <p class="text-sm">No reading goals in the pipeline yet.</p>
          <a href="/reading_goals/new" class="mt-2 text-sm text-indigo-600 hover:text-indigo-500 font-medium">Create a reading goal</a>
        </div>
      `
      return
    }

    this.element.innerHTML = ""

    this.goals = this.chartData.goals
      .filter(g => g.start_date && g.end_date && g.minutes_per_day > 0)
      .map(g => ({
        ...g,
        startDate: new Date(g.start_date + "T00:00:00"),
        endDate: d3.timeDay.offset(new Date(g.end_date + "T00:00:00"), 1)
      }))

    if (this.goals.length === 0) {
      this.element.innerHTML = `
        <div class="flex items-center justify-center h-48 text-gray-500">
          <p>Set dates on your reading goals to see them in the pipeline.</p>
        </div>
      `
      return
    }

    // Sort by duration descending (longest on bottom = Breakout style)
    this.goals.sort((a, b) => b.duration_days - a.duration_days)

    this.goals.forEach((g, i) => {
      g.color = this.constructor.BLOCK_COLORS[i % this.constructor.BLOCK_COLORS.length]
      g._index = i
      g._isQueued = g.goal_status === "queued"
      g._isUnowned = !g.owned
    })

    this.setupScales()
    this.createSvg()
    this.renderDefs()
    this.renderBackground()
    this.renderToday()

    const { bricks, maxY } = this.computeBricks(this.goals)
    this.currentBricks = bricks
    this.renderBricks(bricks)
    this.buildHitBoxes()
    const labels = this.computeLabels(bricks, this.goals)
    this.renderLabels(labels)
    this.renderTimeline()

    this.renderOverlays()

    if (!this.compactValue) {
      this.renderLegend(this.goals)
    }

    // Entrance: single clean fade on the whole chart
    this.svgElement.style("opacity", 0)
    this.svgElement.transition().duration(400).style("opacity", 1)

    this.centerOnToday()
  }

  setupScales() {
    const containerWidth = this.element.clientWidth
    this.width = Math.max(containerWidth, this.minWidth) - this.margin.left - this.margin.right

    const { bricks, maxY } = this.computeBricks(this.goals)
    this.totalMinutes = maxY || 1

    // Generous height — give the pipeline room to breathe
    const minH = this.compactValue ? 150 : 280
    const maxH = this.compactValue ? 250 : 550
    this.chartHeight = Math.min(Math.max(this.totalMinutes * 3, minH), maxH)

    const minDate = d3.min(this.goals, d => d.startDate)
    const maxDate = d3.max(this.goals, d => d.endDate)
    this.startDate = d3.timeDay.offset(minDate, -3)
    this.endDate = d3.timeDay.offset(maxDate, 3)

    this.xScale = d3.scaleTime()
      .domain([this.startDate, this.endDate])
      .range([0, this.width])

    this.yScale = d3.scaleLinear()
      .domain([0, this.totalMinutes])
      .range([this.chartHeight, 0])
  }

  createSvg() {
    const svgWidth = this.width + this.margin.left + this.margin.right
    const svgHeight = this.chartHeight + this.margin.top + this.margin.bottom

    this.svgElement = d3.select(this.element)
      .append("svg")
      .attr("class", "pipeline-svg")
      .attr("width", svgWidth)
      .attr("height", svgHeight)

    // Defs for clip path and gradients
    this.svgElement.append("defs")

    this.svgElement.select("defs")
      .append("clipPath")
      .attr("id", "chart-clip")
      .append("rect")
      .attr("x", -this.margin.left)
      .attr("y", -this.margin.top)
      .attr("width", svgWidth)
      .attr("height", svgHeight)

    const outerG = this.svgElement.append("g")
      .attr("transform", `translate(${this.margin.left},${this.margin.top})`)
      .attr("clip-path", "url(#chart-clip)")

    this.zoomGroup = outerG.append("g").attr("class", "zoom-group")
    this.svg = this.zoomGroup

    // Layers in render order
    this.bgLayer = this.svg.append("g").attr("class", "layer-bg")
    this.todayBgLayer = this.svg.append("g").attr("class", "layer-today-bg")
    this.brickLayer = this.svg.append("g").attr("class", "layer-bricks")
    this.labelLayer = this.svg.append("g").attr("class", "layer-labels")
    this.todayFgLayer = this.svg.append("g").attr("class", "layer-today-fg")
    this.timelineLayer = this.svg.append("g").attr("class", "layer-timeline")
    this.overlayLayer = this.svg.append("g").attr("class", "layer-overlays")

    // No drop-shadow filter — causes ghost artifacts during zoom transforms

    // Zoom behavior
    this.currentTransform = d3.zoomIdentity
    this.zoomBehavior = d3.zoom()
      .scaleExtent([0.3, 8])
      .filter((event) => {
        if (event.type === "wheel") event.preventDefault()
        return true
      })
      .on("zoom", (event) => {
        this.currentTransform = event.transform
        this.zoomGroup.attr("transform", event.transform)
        this.updateZoomIndicator()
      })

    this.svgElement
      .call(this.zoomBehavior)
      .on("dblclick.zoom", null)

    this.renderZoomControls()

    // Tooltip
    this.tooltip = d3.select(this.element)
      .append("div")
      .attr("class", "absolute hidden bg-gray-900/95 text-white text-sm px-4 py-3 rounded-xl shadow-xl pointer-events-none z-50 max-w-xs backdrop-blur-sm")
      .style("border", "1px solid rgba(255,255,255,0.08)")
  }

  renderZoomControls() {
    const controls = d3.select(this.element)
      .append("div")
      .attr("class", "absolute top-3 right-3 flex items-center gap-1 z-40")
      .style("backdrop-filter", "blur(8px)")
      .style("background", "rgba(255,255,255,0.8)")
      .style("border", "1px solid rgba(0,0,0,0.06)")
      .style("border-radius", "8px")
      .style("padding", "2px")
      .style("box-shadow", "0 1px 2px rgba(0,0,0,0.05)")

    const btn = "w-7 h-7 flex items-center justify-center rounded-md text-gray-400 hover:text-gray-700 hover:bg-gray-100/80 cursor-pointer text-sm font-medium select-none transition-colors"

    controls.append("button").attr("class", btn).attr("title", "Zoom out")
      .style("font-size", "15px").html("&minus;")
      .on("click", () => this.zoomBehavior.scaleBy(this.svgElement.transition().duration(200).ease(d3.easeCubicOut), 1 / 1.4))

    this.zoomIndicator = controls.append("span")
      .attr("class", "text-xs text-gray-400 tabular-nums select-none")
      .style("min-width", "34px").style("text-align", "center")
      .text("100%")

    controls.append("button").attr("class", btn).attr("title", "Zoom in")
      .style("font-size", "15px").html("+")
      .on("click", () => this.zoomBehavior.scaleBy(this.svgElement.transition().duration(200).ease(d3.easeCubicOut), 1.4))

    controls.append("div")
      .style("width", "1px").style("height", "14px")
      .style("background", "rgba(0,0,0,0.08)").style("margin", "0 1px")

    controls.append("button").attr("class", btn).attr("title", "Reset view")
      .style("font-size", "12px").html("&#8634;")
      .on("click", () => this.zoomBehavior.transform(this.svgElement.transition().duration(250).ease(d3.easeCubicOut), d3.zoomIdentity))
  }

  updateZoomIndicator() {
    if (this.zoomIndicator) {
      this.zoomIndicator.text(`${Math.round(this.currentTransform.k * 100)}%`)
    }
  }

  centerOnToday() {
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    if (today < this.startDate || today > this.endDate) return

    const todayX = this.xScale(today) + this.margin.left
    const svgWidth = this.width + this.margin.left + this.margin.right
    const offset = svgWidth / 2 - todayX
    if (Math.abs(offset) < 40) return

    this.svgElement
      .transition().duration(600).delay(300).ease(d3.easeCubicInOut)
      .call(this.zoomBehavior.transform, d3.zoomIdentity.translate(offset, 0))
  }

  // ── Defs ──────────────────────────────────────────────────────────

  renderDefs() {
    const defs = this.svgElement.select("defs")

    this.goals.forEach((goal, i) => {
      const queuedDim = goal._isQueued ? 0.5 : 1.0
      const states = [
        { name: "future", color: goal.color, darken: 0, opacity: 0.82 * queuedDim },
        { name: "past", color: goal.color, darken: 0.25, opacity: 0.95 * queuedDim },
        { name: "today", color: goal.color, darken: 0, opacity: 0.82 * queuedDim },
        { name: "today-progress", color: goal.color, darken: 0.25, opacity: 0.95 * queuedDim }
      ]

      states.forEach(({ name, color, darken, opacity }) => {
        const base = darken > 0 ? d3.color(color).darker(darken) : d3.color(color)
        const grad = defs.append("linearGradient")
          .attr("id", `brick-grad-${i}-${name}`)
          .attr("x1", "0%").attr("y1", "0%")
          .attr("x2", "0%").attr("y2", "100%")

        grad.append("stop")
          .attr("offset", "0%")
          .attr("stop-color", d3.color(base).brighter(0.3))
          .attr("stop-opacity", opacity)
        grad.append("stop")
          .attr("offset", "100%")
          .attr("stop-color", d3.color(base).darker(0.15))
          .attr("stop-opacity", opacity)
      })
    })
  }

  // ── Background: minimal grid, month bands ─────────────────────────

  renderBackground() {
    const g = this.bgLayer

    // Soft background
    g.append("rect")
      .attr("x", 0).attr("y", 0)
      .attr("width", this.width).attr("height", this.chartHeight)
      .attr("fill", "#f8fafc")
      .attr("rx", 6)

    // Month bands — alternating subtle shading
    const months = d3.timeMonth.range(
      d3.timeMonth.floor(this.startDate),
      d3.timeMonth.offset(d3.timeMonth.ceil(this.endDate), 1)
    )
    months.forEach((month, i) => {
      if (i % 2 === 0) return
      const nextMonth = d3.timeMonth.offset(month, 1)
      const x1 = Math.max(this.xScale(month), 0)
      const x2 = Math.min(this.xScale(nextMonth), this.width)
      if (x2 <= x1) return
      g.append("rect")
        .attr("x", x1).attr("y", 0)
        .attr("width", x2 - x1).attr("height", this.chartHeight)
        .attr("fill", "#f1f5f9")
    })

    // Weekend shading — very subtle
    const days = []
    let day = d3.timeDay.floor(this.startDate)
    while (day <= this.endDate) { days.push(new Date(day)); day = d3.timeDay.offset(day, 1) }

    days.filter(d => d.getDay() === 0 || d.getDay() === 6).forEach(d => {
      g.append("rect")
        .attr("x", this.xScale(d)).attr("y", 0)
        .attr("width", this.xScale(d3.timeDay.offset(d, 1)) - this.xScale(d))
        .attr("height", this.chartHeight)
        .attr("fill", "#e2e8f0").attr("opacity", 0.25)
    })

    // Horizontal minute lines — faint, no label clutter
    const minuteTicks = this.niceMinuteTicks(this.totalMinutes)
    minuteTicks.forEach(m => {
      if (m === 0) return
      g.append("line")
        .attr("x1", 0).attr("x2", this.width)
        .attr("y1", this.yScale(m)).attr("y2", this.yScale(m))
        .attr("stroke", "#e2e8f0").attr("stroke-dasharray", "1,3")
        .attr("vector-effect", "non-scaling-stroke")
    })

    // Y axis — minimal: just tick values, no axis line
    minuteTicks.forEach(m => {
      if (m === 0) return
      g.append("text")
        .attr("x", -8).attr("y", this.yScale(m))
        .attr("text-anchor", "end").attr("dy", "0.35em")
        .attr("fill", "#94a3b8").attr("font-size", "10px")
        .text(`${m}m`)
    })
  }

  // ── Today column ──────────────────────────────────────────────────

  renderToday() {
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    if (today < this.startDate || today > this.endDate) return

    const todayX = this.xScale(today)
    const dayWidth = this.xScale(d3.timeDay.offset(today, 1)) - todayX

    // Background highlight on today's column
    this.todayBgLayer.append("rect")
      .attr("x", todayX).attr("y", -this.margin.top)
      .attr("width", dayWidth)
      .attr("height", this.chartHeight + this.margin.top + this.margin.bottom)
      .attr("fill", "#fef2f2")
      .attr("opacity", 0.6)

    // Foreground: crisp line + label (rendered above bricks)
    this.todayFgLayer.append("line")
      .attr("x1", todayX).attr("x2", todayX)
      .attr("y1", 0).attr("y2", this.chartHeight)
      .attr("stroke", "#ef4444").attr("stroke-width", 1.5)
      .attr("stroke-dasharray", "6,4").attr("stroke-linecap", "round")
      .attr("vector-effect", "non-scaling-stroke")

    // Pill label
    const pill = this.todayFgLayer.append("g")
      .attr("transform", `translate(${todayX}, -8)`)

    pill.append("rect")
      .attr("x", -18).attr("y", -7)
      .attr("width", 36).attr("height", 14)
      .attr("rx", 7).attr("fill", "#ef4444")

    pill.append("text")
      .attr("text-anchor", "middle").attr("dy", "0.32em")
      .attr("fill", "#fff").attr("font-size", "8px")
      .attr("font-weight", "600").attr("letter-spacing", "0.08em")
      .text("TODAY")
  }

  // ── Timeline (X axis) ─────────────────────────────────────────────

  renderTimeline() {
    const g = this.timelineLayer

    // Month labels along the bottom — clean, no tick marks
    const months = d3.timeMonth.range(
      d3.timeMonth.floor(this.startDate),
      d3.timeMonth.offset(d3.timeMonth.ceil(this.endDate), 1)
    )

    months.forEach(month => {
      const nextMonth = d3.timeMonth.offset(month, 1)
      const x1 = Math.max(this.xScale(month), 0)
      const x2 = Math.min(this.xScale(nextMonth), this.width)
      if (x2 - x1 < 30) return

      // Month separator line
      if (x1 > 0) {
        g.append("line")
          .attr("x1", x1).attr("x2", x1)
          .attr("y1", 0).attr("y2", this.chartHeight)
          .attr("stroke", "#cbd5e1").attr("stroke-width", 0.5)
          .attr("vector-effect", "non-scaling-stroke")
      }

      // Month name
      g.append("text")
        .attr("x", (x1 + x2) / 2)
        .attr("y", this.chartHeight + 20)
        .attr("text-anchor", "middle")
        .attr("fill", "#94a3b8").attr("font-size", "11px")
        .attr("font-weight", "500")
        .text(d3.timeFormat("%B")(month))
    })

    // Week tick marks — tiny dots along the bottom edge
    const weeks = d3.timeWeek.range(this.startDate, this.endDate)
    weeks.forEach(week => {
      const x = this.xScale(week)
      g.append("line")
        .attr("x1", x).attr("x2", x)
        .attr("y1", this.chartHeight).attr("y2", this.chartHeight + 4)
        .attr("stroke", "#cbd5e1").attr("stroke-width", 0.5)
        .attr("vector-effect", "non-scaling-stroke")
    })
  }

  // ── Bricks: grouped by goal ───────────────────────────────────────

  renderBricks(bricks) {
    const gap = 1.5

    // Group bricks by goal
    const bricksByGoal = d3.group(bricks, d => d.goalId)

    this.goalGroups = new Map()

    this.goals.forEach(goal => {
      const goalBricks = bricksByGoal.get(goal.id) || []
      if (!goalBricks.length) return

      const group = this.brickLayer.append("g")
        .attr("class", "goal-group")
        .attr("data-goal-id", goal.id)

      this.goalGroups.set(goal.id, group)

      // Main bricks
      group.selectAll(".brick")
        .data(goalBricks, d => d.key)
        .enter()
        .append("rect")
        .attr("class", "brick")
        .attr("rx", 3).attr("ry", 3)
        .attr("x", d => this.xScale(d.date) + gap / 2)
        .attr("y", d => this.yScale(d.yOffset + d.minutes) + gap / 2)
        .attr("width", d => Math.max(this.xScale(d.nextDate) - this.xScale(d.date) - gap, 1))
        .attr("height", d => Math.max(this.yScale(d.yOffset) - this.yScale(d.yOffset + d.minutes) - gap, 1))
        .attr("fill", d => {
          const state = d.isPast ? "past" : d.isToday ? "today" : "future"
          return `url(#brick-grad-${d.goalIndex}-${state})`
        })
        .attr("stroke", "transparent")
        .attr("stroke-width", 0)

      // Top-edge highlight bevel
      group.selectAll(".brick-highlight")
        .data(goalBricks, d => d.key + "-hl")
        .enter()
        .append("line")
        .attr("class", "brick-highlight")
        .attr("x1", d => this.xScale(d.date) + gap / 2 + 1)
        .attr("x2", d => this.xScale(d.nextDate) - gap / 2 - 1)
        .attr("y1", d => this.yScale(d.yOffset + d.minutes) + gap / 2 + 0.5)
        .attr("y2", d => this.yScale(d.yOffset + d.minutes) + gap / 2 + 0.5)
        .attr("stroke", "rgba(255,255,255,0.3)")
        .attr("stroke-width", 0.5)
        .attr("vector-effect", "non-scaling-stroke")
        .style("pointer-events", "none")

      // Today progress overlay
      const todayBricks = goalBricks.filter(b => b.isToday && b.todayProgress > 0)
      group.selectAll(".brick-today-progress")
        .data(todayBricks, d => d.key + "-progress")
        .enter()
        .append("rect")
        .attr("class", "brick-today-progress")
        .attr("rx", 3).attr("ry", 3)
        .attr("x", d => this.xScale(d.date) + gap / 2)
        .attr("y", d => {
          const progressHeight = Math.min(d.todayProgress, d.minutes)
          return this.yScale(d.yOffset + progressHeight) + gap / 2
        })
        .attr("width", d => Math.max(this.xScale(d.nextDate) - this.xScale(d.date) - gap, 1))
        .attr("height", d => {
          const progressHeight = Math.min(d.todayProgress, d.minutes)
          return Math.max(this.yScale(d.yOffset) - this.yScale(d.yOffset + progressHeight) - gap, 0)
        })
        .attr("fill", d => `url(#brick-grad-${d.goalIndex}-today-progress)`)

      // Unowned borders
      const unownedBricks = goalBricks.filter(b => b.isUnowned)
      group.selectAll(".brick-unowned-border")
        .data(unownedBricks, d => d.key + "-ub")
        .enter()
        .append("rect")
        .attr("class", "brick-unowned-border")
        .attr("rx", 3)
        .attr("fill", "none").attr("stroke", "#f59e0b")
        .attr("stroke-width", 1.5).attr("stroke-dasharray", "2,2")
        .attr("vector-effect", "non-scaling-stroke")
        .style("pointer-events", "none")
        .attr("x", d => this.xScale(d.date) + gap / 2)
        .attr("y", d => this.yScale(d.yOffset + d.minutes) + gap / 2)
        .attr("width", d => Math.max(this.xScale(d.nextDate) - this.xScale(d.date) - gap, 1))
        .attr("height", d => Math.max(this.yScale(d.yOffset) - this.yScale(d.yOffset + d.minutes) - gap, 1))

      // Queued borders
      const queuedBricks = goalBricks.filter(b => b.isQueued)
      group.selectAll(".brick-queued-border")
        .data(queuedBricks, d => d.key + "-qb")
        .enter()
        .append("rect")
        .attr("class", "brick-queued-border")
        .attr("rx", 3)
        .attr("fill", "none").attr("stroke", "rgba(255,255,255,0.4)")
        .attr("stroke-width", 1).attr("stroke-dasharray", "4,3")
        .attr("vector-effect", "non-scaling-stroke")
        .style("pointer-events", "none")
        .attr("x", d => this.xScale(d.date) + gap / 2)
        .attr("y", d => this.yScale(d.yOffset + d.minutes) + gap / 2)
        .attr("width", d => Math.max(this.xScale(d.nextDate) - this.xScale(d.date) - gap, 1))
        .attr("height", d => Math.max(this.yScale(d.yOffset) - this.yScale(d.yOffset + d.minutes) - gap, 1))
    })
  }

  // ── Labels: grouped by goal ───────────────────────────────────────

  renderLabels(labels) {
    // Group labels by goal for CSS-based hover dimming
    const labelsByGoal = d3.group(labels, d => d.goalId)

    this.goals.forEach(goal => {
      const goalLabels = labelsByGoal.get(goal.id) || []
      if (!goalLabels.length) return

      const group = this.labelLayer.append("g")
        .attr("class", "label-group")
        .attr("data-goal-id", goal.id)

      // Title labels
      goalLabels.filter(l => l.width >= 60 && l.height >= 16).forEach(l => {
        group.append("text")
          .attr("class", "label-title")
          .attr("x", l.x).attr("y", l.y)
          .attr("dy", "0.35em")
          .attr("fill", "#fff").attr("font-weight", "600")
          .attr("font-size", l.height >= 28 ? "12px" : "10px")
          .style("text-shadow", "0 1px 2px rgba(0,0,0,0.5)")
          .style("pointer-events", "none")
          .text(() => {
            const maxChars = Math.floor((l.width - 16) / 7)
            return l.title.length > maxChars ? l.title.substring(0, maxChars - 1) + "\u2026" : l.title
          })
      })

      // Minutes/day labels
      if (!this.compactValue) {
        goalLabels.filter(l => l.width >= 80 && l.height >= 16).forEach(l => {
          group.append("text")
            .attr("class", "label-mpd")
            .attr("x", l.xEnd).attr("y", l.y)
            .attr("text-anchor", "end").attr("dy", "0.35em")
            .attr("fill", "rgba(255,255,255,0.75)")
            .attr("font-size", "10px").attr("font-weight", "500")
            .style("text-shadow", "0 1px 2px rgba(0,0,0,0.4)")
            .style("pointer-events", "none")
            .text(`${l.minutesPerDay}m/day`)
        })
      }

      // Estimate indicators
      goalLabels.filter(l => !l.usesActualData && l.width > 20 && l.height > 4).forEach(l => {
        group.append("rect")
          .attr("class", "estimate-indicator")
          .attr("rx", 3)
          .attr("fill", "none").attr("stroke", "rgba(255,255,255,0.25)")
          .attr("stroke-width", 1).attr("stroke-dasharray", "3,3")
          .attr("vector-effect", "non-scaling-stroke")
          .style("pointer-events", "none")
          .attr("x", l.x - 7)
          .attr("y", l.y - l.height / 2 + 1)
          .attr("width", Math.max(l.width - 2, 4))
          .attr("height", Math.max(l.height - 2, 1))
      })
    })
  }

  // ── Overlays: hover + click ───────────────────────────────────────

  renderOverlays() {
    const self = this

    // Precompute tooltip HTML
    this.goals.forEach(goal => {
      const dataSource = goal.uses_actual_data
        ? '<span class="text-green-400">Actual reading speed</span>'
        : '<span class="text-gray-400">Estimated from density</span>'

      let daysLine
      if (goal.goal_status === "completed") {
        daysLine = '<span class="text-green-400">Completed</span>'
      } else if (goal.goal_status === "abandoned") {
        daysLine = '<span class="text-red-400">Abandoned</span>'
      } else if (goal.days_remaining > 0 && goal.startDate <= new Date()) {
        const suffix = !this.includesWeekends ? ` <span class="text-gray-500">(${goal.calendar_days} cal)</span>` : ""
        daysLine = `${goal.days_remaining}d remaining${suffix}`
      } else {
        const suffix = !this.includesWeekends ? ` <span class="text-gray-500">(${goal.calendar_days} cal)</span>` : ""
        daysLine = `${goal.duration_days}d duration${suffix}`
      }

      let actualInfo = ""
      if (goal.actual_minutes_by_date && Object.keys(goal.actual_minutes_by_date).length > 0) {
        const totalMin = Object.values(goal.actual_minutes_by_date).reduce((s, m) => s + m, 0)
        const daysRead = Object.keys(goal.actual_minutes_by_date).length
        actualInfo = `
          <div class="mt-1.5 pt-1.5 border-t border-white/10 text-xs">
            <span class="text-blue-400">${totalMin}m</span> over ${daysRead} days
            <span class="text-gray-500">(${Math.round(totalMin / daysRead)}m/day avg)</span>
          </div>
        `
      }

      const unownedBadge = goal._isUnowned
        ? '<span class="inline-block mt-1 px-1.5 py-0.5 rounded text-xs bg-amber-500/20 text-amber-400">Not yet owned</span>'
        : ''

      goal._tooltipHtml = `
        <div class="flex items-center gap-2 mb-1.5">
          <span style="width:8px;height:8px;border-radius:2px;background:${goal.color};flex-shrink:0"></span>
          <span class="font-semibold text-sm">${goal.title}</span>
        </div>
        <div class="text-gray-400 text-xs">${goal.author || "Unknown author"}</div>
        ${unownedBadge}
        <div class="mt-2 grid grid-cols-2 gap-x-4 gap-y-0.5 text-xs">
          <div><span class="text-gray-500">Plan</span> ${goal.minutes_per_day}m/day</div>
          <div>${daysLine}</div>
          <div><span class="text-gray-500">Pages</span> ${goal.total_pages}</div>
          <div><span class="text-gray-500">Progress</span> ${goal.progress}%</div>
          <div><span class="text-gray-500">Rate</span> ${goal.pages_per_day} pp/d</div>
          <div><span class="text-gray-500">Left</span> ${(goal.estimated_hours || 0).toFixed(1)}h</div>
        </div>
        <div class="mt-1.5 text-xs">${dataSource}</div>
        ${actualInfo}
      `
    })

    this._hoveredGoalId = null

    // Single overlay rect covering the entire chart for event capture
    this.overlayLayer.append("rect")
      .attr("x", 0).attr("y", 0)
      .attr("width", this.width).attr("height", this.chartHeight)
      .attr("fill", "transparent")
      .on("mousemove", (event) => {
        const [mx, my] = d3.pointer(event, self.svg.node())
        const hitGoal = self.findGoalAtPoint(mx, my)

        if (hitGoal) {
          if (self._hoveredGoalId !== hitGoal.id) {
            self.setHoveredGoal(hitGoal.id)
            self.tooltip.html(hitGoal._tooltipHtml).classed("hidden", false)
          }
          const container = self.element.getBoundingClientRect()
          const tip = self.tooltip.node().getBoundingClientRect()
          const cursorX = event.clientX - container.left
          const cursorY = event.clientY - container.top

          // Flip horizontally if tooltip would overflow right edge
          const left = cursorX + 15 + tip.width > container.width
            ? cursorX - tip.width - 10
            : cursorX + 15

          // Flip vertically if tooltip would overflow bottom edge
          const top = cursorY - 10 + tip.height > container.height
            ? cursorY - tip.height - 5
            : cursorY - 10

          self.tooltip
            .style("left", `${Math.max(0, left)}px`)
            .style("top", `${Math.max(0, top)}px`)
        } else {
          self.clearHover()
        }
      })
      .on("mouseleave", () => { self.clearHover() })
      .on("click", (event) => {
        if (event.defaultPrevented) return
        const [mx, my] = d3.pointer(event, self.svg.node())
        const hitGoal = self.findGoalAtPoint(mx, my)
        if (hitGoal) window.location.href = `/reading_goals/${hitGoal.id}`
      })
  }

  setHoveredGoal(goalId) {
    this._hoveredGoalId = goalId
    this.svgElement.attr("data-hovering", "true")

    // Set active on the hovered goal's groups
    this.goalGroups.forEach((group, id) => {
      if (id === goalId) group.attr("data-active", "true")
      else group.attr("data-active", null)
    })

    // Label groups
    this.labelLayer.selectAll(".label-group").each(function() {
      const el = d3.select(this)
      if (parseInt(el.attr("data-goal-id")) === goalId) el.attr("data-active", "true")
      else el.attr("data-active", null)
    })
  }

  clearHover() {
    if (!this._hoveredGoalId) return
    this._hoveredGoalId = null
    this.svgElement.attr("data-hovering", null)

    this.goalGroups.forEach((group) => { group.attr("data-active", null) })
    this.labelLayer.selectAll(".label-group").attr("data-active", null)

    this.tooltip.classed("hidden", true)
  }

  // ── Hit testing ───────────────────────────────────────────────────

  // Precompute per-goal bounding boxes for generous hit targets.
  // Called once after bricks are rendered. Each bbox spans the full
  // date range and vertical extent of all the goal's bricks.
  buildHitBoxes() {
    const gap = 1.5
    this.goalHitBoxes = []

    this.goals.forEach(goal => {
      const goalBricks = this.currentBricks.filter(b => b.goalId === goal.id)
      if (!goalBricks.length) return

      const x1 = d3.min(goalBricks, b => this.xScale(b.date) + gap / 2)
      const x2 = d3.max(goalBricks, b => this.xScale(b.nextDate) - gap / 2)
      const y1 = d3.min(goalBricks, b => this.yScale(b.yOffset + b.minutes) + gap / 2)
      const y2 = d3.max(goalBricks, b => this.yScale(b.yOffset) - gap / 2)

      this.goalHitBoxes.push({ goal, x1, x2, y1, y2 })
    })

    // Reverse so topmost (last-rendered, shortest duration) is checked first
    this.goalHitBoxes.reverse()
  }

  findGoalAtPoint(mx, my) {
    if (!this.goalHitBoxes) return null
    for (const box of this.goalHitBoxes) {
      if (mx >= box.x1 && mx <= box.x2 && my >= box.y1 && my <= box.y2) {
        return box.goal
      }
    }
    return null
  }

  // ── Legend ─────────────────────────────────────────────────────────

  renderLegend(goals) {
    const legend = d3.select(this.element)
      .append("div")
      .attr("class", "flex flex-wrap gap-x-4 gap-y-1.5 mt-3 justify-center")

    legend.selectAll(".legend-item")
      .data(goals)
      .enter()
      .append("div")
      .attr("class", "legend-item flex items-center gap-1.5 text-xs")
      .html(d => `
        <span class="w-2.5 h-2.5 rounded-sm" style="background:${d.color}"></span>
        <span class="text-gray-500">${d.title}</span>
        ${!d.uses_actual_data ? '<span class="text-gray-300">(est)</span>' : ''}
      `)

    if (goals.some(g => g._isUnowned)) {
      legend.append("div")
        .attr("class", "legend-item flex items-center gap-1.5 text-xs")
        .html(`
          <span class="w-2.5 h-2.5 rounded-sm border border-dashed" style="border-color:#f59e0b"></span>
          <span class="text-gray-500">Unowned</span>
        `)
    }
  }

  // ── Utilities ─────────────────────────────────────────────────────

  niceMinuteTicks(totalMinutes) {
    if (totalMinutes <= 30) return d3.range(0, totalMinutes + 1, 5)
    if (totalMinutes <= 60) return d3.range(0, totalMinutes + 1, 10)
    if (totalMinutes <= 120) return d3.range(0, totalMinutes + 1, 15)
    if (totalMinutes <= 240) return d3.range(0, totalMinutes + 1, 30)
    return d3.range(0, totalMinutes + 1, 60)
  }

  debounce(func, wait) {
    let timeout
    return (...args) => {
      clearTimeout(timeout)
      timeout = setTimeout(() => func.apply(this, args), wait)
    }
  }
}
