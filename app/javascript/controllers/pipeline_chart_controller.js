import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"

// Connects to data-controller="pipeline-chart"
export default class extends Controller {
  static values = {
    url: String,
    compact: { type: Boolean, default: false }
  }

  // Vibrant Breakout-style color palette
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
      ? { top: 20, right: 20, bottom: 40, left: 50 }
      : { top: 30, right: 30, bottom: 50, left: 60 }
    this.minWidth = 400

    this.loadData()

    this.resizeHandler = this.debounce(() => this.render(), 250)
    window.addEventListener("resize", this.resizeHandler)

    // Listen for reading list changes to refresh the chart
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

  // ── Data computation ──────────────────────────────────────────────

  // Compute per-day bricks for all goals. Each day is its own brick.
  // Past days use actual reading time, future days use planned time.
  // Returns { bricks: [...], maxY: number }
  computeBricks(goals) {
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const todayTime = today.getTime()
    const dayMs = 86400000

    // Find date range across all goals
    const earliest = d3.min(goals, g => g.startDate)
    const latest = d3.max(goals, g => g.endDate)

    // Helper to get actual minutes for a goal on a specific date
    const getActualMinutes = (goal, dateStr) => {
      if (!goal.actual_minutes_by_date) return 0
      return goal.actual_minutes_by_date[dateStr] || 0
    }

    // Iterate day by day across the full range
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

      // Which goals are active on this day?
      const active = goals.filter(g => {
        if (g.startDate.getTime() > dayTime || g.endDate.getTime() <= dayTime) return false
        if (isWeekend && !this.includesWeekends) return false
        return true
      })

      // Compute height for each active goal on this day
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

    // Also ensure maxY covers planned minutes_per_day
    goals.forEach(g => { maxY = Math.max(maxY, g.minutes_per_day) })

    return { bricks, maxY }
  }

  // Compute label positions: find widest contiguous brick run per goal
  computeLabels(bricks, goals) {
    const labels = []
    goals.forEach(goal => {
      const goalBricks = bricks
        .filter(b => b.goalId === goal.id)
        .sort((a, b) => a.date - b.date)
      if (!goalBricks.length) return

      // Group into contiguous date runs
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

      // Find the run with widest pixel span
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

      // Use average yOffset and minutes for vertical positioning
      const avgYOffset = d3.mean(widestRun, d => d.yOffset)
      const avgMinutes = d3.mean(widestRun, d => d.minutes)
      const labelHeight = this.yScale(avgYOffset) - this.yScale(avgYOffset + avgMinutes)

      labels.push({
        goalId: goal.id,
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

    // Parse and prepare goals
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

    // Assign colors and indices
    this.goals.forEach((g, i) => {
      g.color = this.constructor.BLOCK_COLORS[i % this.constructor.BLOCK_COLORS.length]
      g._index = i
      g._isQueued = g.goal_status === "queued"
      g._isUnowned = !g.owned
    })

    this.setupScales()
    this.createSvg()
    this.renderDefs()
    this.renderGrid()

    // Compute and render bricks
    const { bricks, maxY } = this.computeBricks(this.goals)
    this.currentBricks = bricks
    this.renderBricks(bricks, { animate: true })
    const labels = this.computeLabels(bricks, this.goals)
    this.renderLabels(labels, { animate: true })

    this.renderOverlays()

    if (!this.compactValue) {
      this.renderLegend(this.goals)
    }

    // Auto-center on today after entrance animation
    this.centerOnToday()
  }

  setupScales() {
    const containerWidth = this.element.clientWidth
    this.width = Math.max(containerWidth, this.minWidth) - this.margin.left - this.margin.right

    // Compute bricks to determine maxY for scale
    const { bricks, maxY } = this.computeBricks(this.goals)
    this.totalMinutes = maxY || 1

    // Dynamic chart height
    const minH = this.compactValue ? 150 : 250
    const maxH = this.compactValue ? 250 : 500
    this.chartHeight = Math.min(Math.max(this.totalMinutes * 2.5, minH), maxH)

    // Date range with padding
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
      .attr("width", svgWidth)
      .attr("height", svgHeight)
      .style("cursor", "grab")

    // Clip path to contain zoomed content within chart area
    const defs = this.svgElement.append("defs")
    defs.append("clipPath")
      .attr("id", "chart-clip")
      .append("rect")
      .attr("x", -this.margin.left)
      .attr("y", -this.margin.top)
      .attr("width", svgWidth)
      .attr("height", svgHeight)

    // Outer group for margin offset + clipping
    const outerG = this.svgElement.append("g")
      .attr("transform", `translate(${this.margin.left},${this.margin.top})`)
      .attr("clip-path", "url(#chart-clip)")

    // Zoom wrapper group — d3.zoom transforms this
    this.zoomGroup = outerG.append("g")
      .attr("class", "zoom-group")

    // The svg reference used by all render methods
    this.svg = this.zoomGroup

    // Create layers
    this.gridLayer = this.svg.append("g").attr("class", "layer-grid")
    this.brickLayer = this.svg.append("g").attr("class", "layer-bricks")
    this.labelLayer = this.svg.append("g").attr("class", "layer-labels")
    this.overlayLayer = this.svg.append("g").attr("class", "layer-overlays")

    // Richer drop shadow on bricks
    this.brickLayer.style("filter", "drop-shadow(0 2px 4px rgba(0,0,0,0.18))")

    // Set up d3.zoom
    this.currentTransform = d3.zoomIdentity
    this.zoomBehavior = d3.zoom()
      .scaleExtent([0.3, 8])
      .filter((event) => {
        if (event.type === "wheel") {
          event.preventDefault()
        }
        return true
      })
      .on("zoom", (event) => {
        this.currentTransform = event.transform
        this.zoomGroup.attr("transform", event.transform)
        this.updateZoomIndicator()
      })
      .on("start", () => {
        this.svgElement.style("cursor", "grabbing")
      })
      .on("end", () => {
        this.svgElement.style("cursor", "grab")
      })

    this.svgElement
      .call(this.zoomBehavior)
      .on("dblclick.zoom", null) // disable double-click zoom (interferes with brick clicks)

    // Zoom controls
    this.renderZoomControls()

    // Tooltip (DOM element, not SVG)
    this.tooltip = d3.select(this.element)
      .append("div")
      .attr("class", "absolute hidden bg-gray-900/95 text-white text-sm px-4 py-3 rounded-xl shadow-xl pointer-events-none z-50 max-w-xs backdrop-blur-sm")
      .style("transition", "opacity 0.15s, transform 0.15s")
      .style("border", "1px solid rgba(255,255,255,0.1)")
  }

  renderZoomControls() {
    const controls = d3.select(this.element)
      .append("div")
      .attr("class", "absolute top-3 right-3 flex items-center gap-1 z-40")
      .style("backdrop-filter", "blur(8px)")
      .style("background", "rgba(255,255,255,0.85)")
      .style("border", "1px solid rgba(0,0,0,0.08)")
      .style("border-radius", "8px")
      .style("padding", "2px")
      .style("box-shadow", "0 1px 3px rgba(0,0,0,0.08)")

    const buttonClass = "w-7 h-7 flex items-center justify-center rounded-md text-gray-500 hover:text-gray-800 hover:bg-gray-100/80 cursor-pointer text-sm font-medium select-none transition-colors"

    controls.append("button")
      .attr("class", buttonClass)
      .attr("title", "Zoom out")
      .style("font-size", "16px")
      .html("&minus;")
      .on("click", () => this.zoomBehavior.scaleBy(this.svgElement.transition().duration(250).ease(d3.easeCubicOut), 1 / 1.5))

    this.zoomIndicator = controls.append("span")
      .attr("class", "text-xs text-gray-400 font-medium tabular-nums select-none")
      .style("min-width", "36px")
      .style("text-align", "center")
      .text("100%")

    controls.append("button")
      .attr("class", buttonClass)
      .attr("title", "Zoom in")
      .style("font-size", "16px")
      .html("+")
      .on("click", () => this.zoomBehavior.scaleBy(this.svgElement.transition().duration(250).ease(d3.easeCubicOut), 1.5))

    // Divider
    controls.append("div")
      .style("width", "1px")
      .style("height", "16px")
      .style("background", "rgba(0,0,0,0.1)")
      .style("margin", "0 2px")

    controls.append("button")
      .attr("class", buttonClass)
      .attr("title", "Reset view")
      .style("font-size", "13px")
      .html("&#8634;")
      .on("click", () => this.zoomBehavior.transform(this.svgElement.transition().duration(300).ease(d3.easeCubicOut), d3.zoomIdentity))
  }

  updateZoomIndicator() {
    if (this.zoomIndicator) {
      const pct = Math.round(this.currentTransform.k * 100)
      this.zoomIndicator.text(`${pct}%`)
    }
  }

  centerOnToday() {
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    if (today < this.startDate || today > this.endDate) return

    const todayX = this.xScale(today) + this.margin.left
    const svgWidth = this.width + this.margin.left + this.margin.right
    const centerX = svgWidth / 2

    // Only pan if today is far enough from center to matter
    const offset = centerX - todayX
    if (Math.abs(offset) < 50) return

    const t = d3.zoomIdentity.translate(offset, 0)
    this.svgElement
      .transition()
      .duration(800)
      .delay(400) // wait for entrance animation
      .ease(d3.easeCubicInOut)
      .call(this.zoomBehavior.transform, t)
  }

  renderDefs() {
    const defs = this.svgElement.select("defs")

    // Glow filter for hover effect
    const glow = defs.append("filter")
      .attr("id", "brick-glow")
      .attr("x", "-30%").attr("y", "-30%")
      .attr("width", "160%").attr("height", "160%")
    glow.append("feGaussianBlur")
      .attr("in", "SourceAlpha")
      .attr("stdDeviation", "3")
      .attr("result", "blur")
    glow.append("feFlood")
      .attr("flood-color", "rgba(255,255,255,0.5)")
      .attr("result", "color")
    glow.append("feComposite")
      .attr("in", "color")
      .attr("in2", "blur")
      .attr("operator", "in")
      .attr("result", "glow")
    const glowMerge = glow.append("feMerge")
    glowMerge.append("feMergeNode").attr("in", "glow")
    glowMerge.append("feMergeNode").attr("in", "SourceGraphic")

    // Today pulse glow
    const todayGlow = defs.append("filter")
      .attr("id", "today-glow")
      .attr("x", "-50%").attr("y", "-50%")
      .attr("width", "200%").attr("height", "200%")
    todayGlow.append("feGaussianBlur")
      .attr("in", "SourceGraphic")
      .attr("stdDeviation", "3")
      .attr("result", "blur")
    const todayMerge = todayGlow.append("feMerge")
    todayMerge.append("feMergeNode").attr("in", "blur")
    todayMerge.append("feMergeNode").attr("in", "SourceGraphic")

    this.goals.forEach((goal, i) => {
      const queuedDim = goal._isQueued ? 0.5 : 1.0
      const states = [
        { name: "future", color: goal.color, darken: 0, opacity: 0.88 * queuedDim },
        { name: "past", color: goal.color, darken: 0.3, opacity: 0.95 * queuedDim },
        { name: "today", color: goal.color, darken: 0, opacity: 0.88 * queuedDim },
        { name: "today-progress", color: goal.color, darken: 0.3, opacity: 0.95 * queuedDim }
      ]

      states.forEach(({ name, color, darken, opacity }) => {
        const base = darken > 0 ? d3.color(color).darker(darken) : d3.color(color)
        const grad = defs.append("linearGradient")
          .attr("id", `brick-grad-${i}-${name}`)
          .attr("x1", "0%").attr("y1", "0%")
          .attr("x2", "0%").attr("y2", "100%")

        grad.append("stop")
          .attr("offset", "0%")
          .attr("stop-color", d3.color(base).brighter(0.35))
          .attr("stop-opacity", opacity)
        grad.append("stop")
          .attr("offset", "50%")
          .attr("stop-color", base)
          .attr("stop-opacity", opacity)
        grad.append("stop")
          .attr("offset", "100%")
          .attr("stop-color", d3.color(base).darker(0.25))
          .attr("stop-opacity", opacity)
      })
    })
  }

  renderGrid() {
    const g = this.gridLayer

    // Subtle chart background gradient
    const bgGrad = this.svgElement.select("defs").append("linearGradient")
      .attr("id", "chart-bg-grad")
      .attr("x1", "0%").attr("y1", "0%")
      .attr("x2", "0%").attr("y2", "100%")
    bgGrad.append("stop").attr("offset", "0%").attr("stop-color", "#fafbfc")
    bgGrad.append("stop").attr("offset", "100%").attr("stop-color", "#f1f5f9")

    g.append("rect")
      .attr("x", 0).attr("y", 0)
      .attr("width", this.width)
      .attr("height", this.chartHeight)
      .attr("fill", "url(#chart-bg-grad)")
      .attr("rx", 4)

    // Day-column grid: vertical line for each day
    const days = []
    let day = d3.timeDay.floor(this.startDate)
    while (day <= this.endDate) {
      days.push(new Date(day))
      day = d3.timeDay.offset(day, 1)
    }

    // Day grid lines
    g.selectAll(".day-line")
      .data(days)
      .enter()
      .append("line")
      .attr("class", "day-line")
      .attr("x1", d => this.xScale(d))
      .attr("x2", d => this.xScale(d))
      .attr("y1", 0)
      .attr("y2", this.chartHeight)
      .style("stroke", "#e2e8f0")
      .style("stroke-width", 0.5)

    // Horizontal grid lines (minutes)
    const minuteTicks = this.niceMinuteTicks(this.totalMinutes)
    g.selectAll(".minute-line")
      .data(minuteTicks)
      .enter()
      .append("line")
      .attr("class", "minute-line")
      .attr("x1", 0)
      .attr("x2", this.width)
      .attr("y1", d => this.yScale(d))
      .attr("y2", d => this.yScale(d))
      .style("stroke", "#e2e8f0")
      .style("stroke-dasharray", "2,4")

    // Weekend shading
    const weekendDays = days.filter(d => d.getDay() === 0 || d.getDay() === 6)
    g.selectAll(".weekend-shade")
      .data(weekendDays)
      .enter()
      .append("rect")
      .attr("class", "weekend-shade")
      .attr("x", d => this.xScale(d))
      .attr("y", 0)
      .attr("width", d => this.xScale(d3.timeDay.offset(d, 1)) - this.xScale(d))
      .attr("height", this.chartHeight)
      .style("fill", "#e2e8f0")
      .style("opacity", 0.35)

    // X axis
    g.append("g")
      .attr("class", "x-axis")
      .attr("transform", `translate(0,${this.chartHeight})`)
      .call(
        d3.axisBottom(this.xScale)
          .ticks(d3.timeWeek.every(1))
          .tickFormat(d3.timeFormat("%b %d"))
      )
      .selectAll("text")
      .style("font-size", "11px")
      .style("fill", "#94a3b8")

    // Style axis lines
    g.select(".x-axis .domain").style("stroke", "#cbd5e1")
    g.selectAll(".x-axis .tick line").style("stroke", "#cbd5e1")

    // Y axis
    g.append("g")
      .attr("class", "y-axis")
      .call(
        d3.axisLeft(this.yScale)
          .tickValues(minuteTicks)
          .tickFormat(d => `${d}m`)
      )
      .selectAll("text")
      .style("font-size", "11px")
      .style("fill", "#94a3b8")

    g.select(".y-axis .domain").style("stroke", "#cbd5e1")
    g.selectAll(".y-axis .tick line").style("stroke", "#cbd5e1")

    // Y axis label
    if (!this.compactValue) {
      g.append("text")
        .attr("transform", "rotate(-90)")
        .attr("y", -this.margin.left + 14)
        .attr("x", -this.chartHeight / 2)
        .attr("text-anchor", "middle")
        .style("fill", "#94a3b8")
        .style("font-size", "11px")
        .style("letter-spacing", "0.05em")
        .text("minutes / day")
    }

    // Today marker — glowing red line with pulse
    const todayDate = new Date()
    if (todayDate >= this.startDate && todayDate <= this.endDate) {
      const todayX = this.xScale(todayDate)

      // Glow behind the line
      g.append("line")
        .attr("class", "today-glow")
        .attr("x1", todayX).attr("x2", todayX)
        .attr("y1", -5).attr("y2", this.chartHeight + 5)
        .style("stroke", "#ef4444")
        .style("stroke-width", 6)
        .style("opacity", 0.15)
        .style("filter", "url(#today-glow)")

      // Animated pulse layer
      const pulse = g.append("line")
        .attr("class", "today-pulse")
        .attr("x1", todayX).attr("x2", todayX)
        .attr("y1", -5).attr("y2", this.chartHeight + 5)
        .style("stroke", "#ef4444")
        .style("stroke-width", 8)
        .style("opacity", 0)

      // Pulse animation loop
      const doPulse = () => {
        pulse
          .style("opacity", 0.12)
          .transition().duration(1500).ease(d3.easeSinOut)
          .style("opacity", 0)
          .on("end", () => {
            setTimeout(doPulse, 2000)
          })
      }
      setTimeout(doPulse, 1000)

      // Main today line
      g.append("line")
        .attr("x1", todayX).attr("x2", todayX)
        .attr("y1", 0).attr("y2", this.chartHeight)
        .style("stroke", "#ef4444")
        .style("stroke-width", 2)
        .style("stroke-dasharray", "6,4")
        .style("stroke-linecap", "round")

      // Today label with pill background
      const labelG = g.append("g").attr("transform", `translate(${todayX}, -12)`)
      labelG.append("rect")
        .attr("x", -20).attr("y", -8)
        .attr("width", 40).attr("height", 16)
        .attr("rx", 8)
        .style("fill", "#ef4444")
      labelG.append("text")
        .attr("text-anchor", "middle")
        .attr("dy", "0.35em")
        .style("fill", "#fff")
        .style("font-size", "9px")
        .style("font-weight", "600")
        .style("letter-spacing", "0.05em")
        .text("TODAY")
    }
  }

  renderBricks(bricks, opts = {}) {
    const gap = 1.5
    const animate = opts.animate && !this.compactValue

    // ── Main brick rects ──
    const join = this.brickLayer.selectAll(".brick")
      .data(bricks, d => d.key)

    join.exit().remove()

    const enter = join.enter()
      .append("rect")
      .attr("class", "brick")
      .attr("rx", 3)
      .attr("ry", 3)

    const applyAttrs = (sel) => {
      sel
        .attr("x", d => this.xScale(d.date) + gap / 2)
        .attr("y", d => this.yScale(d.yOffset + d.minutes) + gap / 2)
        .attr("width", d => Math.max(this.xScale(d.nextDate) - this.xScale(d.date) - gap, 1))
        .attr("height", d => Math.max(this.yScale(d.yOffset) - this.yScale(d.yOffset + d.minutes) - gap, 1))
        .attr("fill", d => {
          const state = d.isPast ? "past" : d.isToday ? "today" : "future"
          return `url(#brick-grad-${d.goalIndex}-${state})`
        })
    }

    if (animate) {
      // Entrance: bricks fade+scale in, staggered left-to-right
      const dateExtent = d3.extent(bricks, d => d.date.getTime())
      const dateRange = dateExtent[1] - dateExtent[0] || 1
      const totalStagger = 400 // ms spread across all columns

      enter
        .style("opacity", 0)
        .attr("transform", d => {
          const cx = this.xScale(d.date) + (this.xScale(d.nextDate) - this.xScale(d.date)) / 2
          const cy = this.yScale(d.yOffset + d.minutes / 2)
          return `translate(${cx}, ${cy}) scale(0.3) translate(${-cx}, ${-cy})`
        })

      applyAttrs(enter)

      enter.transition()
        .duration(300)
        .delay(d => {
          const progress = (d.date.getTime() - dateExtent[0]) / dateRange
          return progress * totalStagger
        })
        .ease(d3.easeBackOut.overshoot(0.6))
        .style("opacity", 1)
        .attr("transform", null)
    } else {
      applyAttrs(enter)
    }

    applyAttrs(join)

    // ── Today progress overlay bricks ──
    const todayBricks = bricks.filter(b => b.isToday && b.todayProgress > 0)

    const progressJoin = this.brickLayer.selectAll(".brick-today-progress")
      .data(todayBricks, d => d.key + "-progress")

    progressJoin.exit().remove()

    const progressEnter = progressJoin.enter()
      .append("rect")
      .attr("class", "brick-today-progress")
      .attr("rx", 3)
      .attr("ry", 3)

    const applyProgress = (sel) => {
      sel
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
    }

    if (animate) {
      progressEnter.style("opacity", 0)
      applyProgress(progressEnter)
      progressEnter.transition().duration(400).delay(500).style("opacity", 1)
    } else {
      applyProgress(progressEnter)
    }
    applyProgress(progressJoin)

    // ── Highlight lines (top edge bevel) ──
    const highlightJoin = this.brickLayer.selectAll(".brick-highlight")
      .data(bricks, d => d.key + "-hl")

    highlightJoin.exit().remove()

    const hlEnter = highlightJoin.enter()
      .append("line")
      .attr("class", "brick-highlight")
      .style("stroke", "rgba(255,255,255,0.35)")
      .style("stroke-width", 0.75)
      .style("pointer-events", "none")

    const applyHighlight = (sel) => {
      sel
        .attr("x1", d => this.xScale(d.date) + gap / 2 + 1)
        .attr("x2", d => this.xScale(d.nextDate) - gap / 2 - 1)
        .attr("y1", d => this.yScale(d.yOffset + d.minutes) + gap / 2 + 0.5)
        .attr("y2", d => this.yScale(d.yOffset + d.minutes) + gap / 2 + 0.5)
    }

    if (animate) {
      hlEnter.style("opacity", 0)
      applyHighlight(hlEnter)
      hlEnter.transition().duration(300).delay(500).style("opacity", 1)
    } else {
      applyHighlight(hlEnter)
    }
    applyHighlight(highlightJoin)

    // ── Unowned goal amber dotted borders ──
    const unownedBricks = bricks.filter(b => b.isUnowned)
    const unownedJoin = this.brickLayer.selectAll(".brick-unowned-border")
      .data(unownedBricks, d => d.key + "-ub")

    unownedJoin.exit().remove()

    const ubEnter = unownedJoin.enter()
      .append("rect")
      .attr("class", "brick-unowned-border")
      .attr("rx", 3)
      .style("fill", "none")
      .style("stroke", "#f59e0b")
      .style("stroke-width", 1.5)
      .style("stroke-dasharray", "2,2")
      .style("pointer-events", "none")

    const applyUnowned = (sel) => {
      sel
        .attr("x", d => this.xScale(d.date) + gap / 2)
        .attr("y", d => this.yScale(d.yOffset + d.minutes) + gap / 2)
        .attr("width", d => Math.max(this.xScale(d.nextDate) - this.xScale(d.date) - gap, 1))
        .attr("height", d => Math.max(this.yScale(d.yOffset) - this.yScale(d.yOffset + d.minutes) - gap, 1))
    }

    applyUnowned(ubEnter)
    applyUnowned(unownedJoin)

    // ── Queued goal dashed borders ──
    const queuedBricks = bricks.filter(b => b.isQueued)
    const queuedJoin = this.brickLayer.selectAll(".brick-queued-border")
      .data(queuedBricks, d => d.key + "-qb")

    queuedJoin.exit().remove()

    const qbEnter = queuedJoin.enter()
      .append("rect")
      .attr("class", "brick-queued-border")
      .attr("rx", 3)
      .style("fill", "none")
      .style("stroke", "rgba(255,255,255,0.4)")
      .style("stroke-width", 1)
      .style("stroke-dasharray", "4,3")
      .style("pointer-events", "none")

    const applyQueued = (sel) => {
      sel
        .attr("x", d => this.xScale(d.date) + gap / 2)
        .attr("y", d => this.yScale(d.yOffset + d.minutes) + gap / 2)
        .attr("width", d => Math.max(this.xScale(d.nextDate) - this.xScale(d.date) - gap, 1))
        .attr("height", d => Math.max(this.yScale(d.yOffset) - this.yScale(d.yOffset + d.minutes) - gap, 1))
    }

    applyQueued(qbEnter)
    applyQueued(queuedJoin)
  }

  renderLabels(labels, opts = {}) {
    const animate = opts.animate && !this.compactValue

    // Title labels
    const titleJoin = this.labelLayer.selectAll(".label-title")
      .data(labels.filter(l => l.width >= 60 && l.height >= 16), d => d.goalId + "-title")

    titleJoin.exit().remove()

    const titleEnter = titleJoin.enter()
      .append("text")
      .attr("class", "label-title")
      .style("fill", "#fff")
      .style("font-weight", "600")
      .style("text-shadow", "0 1px 3px rgba(0,0,0,0.5)")
      .style("pointer-events", "none")
      .attr("dy", "0.35em")

    const applyTitle = (sel) => {
      sel
        .attr("x", d => d.x)
        .attr("y", d => d.y)
        .style("font-size", d => d.height >= 28 ? "12px" : "10px")
        .text(d => {
          const maxChars = Math.floor((d.width - 16) / 7)
          return d.title.length > maxChars ? d.title.substring(0, maxChars - 1) + "\u2026" : d.title
        })
    }

    if (animate) {
      titleEnter.style("opacity", 0)
      applyTitle(titleEnter)
      titleEnter.transition().duration(300).delay(500).style("opacity", 1)
    } else {
      applyTitle(titleEnter)
    }
    applyTitle(titleJoin)

    // Minutes/day labels
    if (!this.compactValue) {
      const mpdJoin = this.labelLayer.selectAll(".label-mpd")
        .data(labels.filter(l => l.width >= 80 && l.height >= 16), d => d.goalId + "-mpd")

      mpdJoin.exit().remove()

      const mpdEnter = mpdJoin.enter()
        .append("text")
        .attr("class", "label-mpd")
        .attr("text-anchor", "end")
        .style("fill", "rgba(255,255,255,0.8)")
        .style("font-size", "10px")
        .style("font-weight", "500")
        .style("text-shadow", "0 1px 3px rgba(0,0,0,0.5)")
        .style("pointer-events", "none")
        .attr("dy", "0.35em")

      const applyMpd = (sel) => {
        sel
          .attr("x", d => d.xEnd)
          .attr("y", d => d.y)
          .text(d => `${d.minutesPerDay}m/day`)
      }

      if (animate) {
        mpdEnter.style("opacity", 0)
        applyMpd(mpdEnter)
        mpdEnter.transition().duration(300).delay(600).style("opacity", 1)
      } else {
        applyMpd(mpdEnter)
      }
      applyMpd(mpdJoin)
    }

    // Estimate indicators (dashed border on widest run for goals without actual data)
    const estimateLabels = labels.filter(l => !l.usesActualData && l.width > 20 && l.height > 4)
    const estJoin = this.labelLayer.selectAll(".estimate-indicator")
      .data(estimateLabels, d => d.goalId + "-est")

    estJoin.exit().remove()

    const estEnter = estJoin.enter()
      .append("rect")
      .attr("class", "estimate-indicator")
      .attr("rx", 3)
      .style("fill", "none")
      .style("stroke", "rgba(255,255,255,0.3)")
      .style("stroke-width", 1)
      .style("stroke-dasharray", "3,3")
      .style("pointer-events", "none")

    const applyEst = (sel) => {
      sel
        .attr("x", d => d.x - 7)
        .attr("y", d => d.y - d.height / 2 + 1)
        .attr("width", d => Math.max(d.width - 2, 4))
        .attr("height", d => Math.max(d.height - 2, 1))
    }

    applyEst(estEnter)
    applyEst(estJoin)
  }

  // ── Overlays (hover, drag, resize, click) ─────────────────────────

  renderOverlays() {
    const self = this
    const today = new Date()
    today.setHours(0, 0, 0, 0)

    // Precompute tooltip HTML for each goal
    this.goals.forEach(goal => {
      const dataSource = goal.uses_actual_data
        ? '<span class="text-green-400">Based on actual reading speed</span>'
        : '<span class="text-gray-400">Estimated from density</span>'

      let daysLine
      if (goal.goal_status === "completed") {
        daysLine = '<span class="text-green-400">Completed</span>'
      } else if (goal.goal_status === "abandoned") {
        daysLine = '<span class="text-red-400">Abandoned</span>'
      } else if (goal.days_remaining > 0 && goal.startDate <= new Date()) {
        const suffix = !this.includesWeekends ? ` <span class="text-gray-500">(${goal.calendar_days} calendar)</span>` : ""
        daysLine = `${goal.days_remaining} days remaining${suffix}`
      } else {
        const suffix = !this.includesWeekends ? ` <span class="text-gray-500">(${goal.calendar_days} calendar)</span>` : ""
        daysLine = `${goal.duration_days} day duration${suffix}`
      }

      let actualTimeInfo = ""
      if (goal.actual_minutes_by_date && Object.keys(goal.actual_minutes_by_date).length > 0) {
        const totalActualMinutes = Object.values(goal.actual_minutes_by_date).reduce((sum, m) => sum + m, 0)
        const daysWithReading = Object.keys(goal.actual_minutes_by_date).length
        const avgPerDay = Math.round(totalActualMinutes / daysWithReading)
        actualTimeInfo = `
          <div class="mt-1 pt-1 border-t border-gray-700">
            <div><span class="text-blue-400">Actual read:</span> ${totalActualMinutes}m over ${daysWithReading} days</div>
            <div><span class="text-blue-400">Avg actual:</span> ${avgPerDay}m/day</div>
          </div>
        `
      }

      const unownedLine = goal._isUnowned
        ? '<div class="text-amber-400 font-medium">Not yet owned</div>'
        : ''

      // Color swatch in tooltip header
      goal._tooltipHtml = `
        <div class="flex items-center gap-2 mb-1">
          <span style="width:10px;height:10px;border-radius:3px;background:${goal.color};display:inline-block;flex-shrink:0"></span>
          <span class="font-semibold">${goal.title}</span>
        </div>
        <div class="text-gray-300 text-xs">${goal.author || "Unknown author"}</div>
        ${unownedLine}
        <div class="mt-2 space-y-1 text-xs">
          <div><span class="text-gray-400">Planned:</span> ${goal.minutes_per_day}m/day</div>
          <div>${daysLine}</div>
          <div><span class="text-gray-400">Pages:</span> ${goal.total_pages}</div>
          <div><span class="text-gray-400">Progress:</span> ${goal.progress}%</div>
          <div><span class="text-gray-400">Pages/day:</span> ${goal.pages_per_day}</div>
          <div><span class="text-gray-400">Est. remaining:</span> ${(goal.estimated_hours || 0).toFixed(1)}h</div>
          <div>${dataSource}</div>
          ${actualTimeInfo}
        </div>
      `
    })

    this._hoveredGoalId = null

    this.goals.forEach(goal => {
      const goalBricks = this.currentBricks.filter(b => b.goalId === goal.id)
      if (!goalBricks.length) return

      // Compute bounding box for this goal's bricks
      const minX = d3.min(goalBricks, b => this.xScale(b.date))
      const maxX = d3.max(goalBricks, b => this.xScale(b.nextDate))
      const minY = d3.min(goalBricks, b => this.yScale(b.yOffset + b.minutes))
      const maxY = d3.max(goalBricks, b => this.yScale(b.yOffset))

      // Invisible hit target covering all bricks for this goal
      const hitTarget = this.overlayLayer.append("rect")
        .attr("class", "overlay-hit")
        .attr("x", minX)
        .attr("y", minY)
        .attr("width", maxX - minX)
        .attr("height", maxY - minY)
        .style("fill", "transparent")
        .style("stroke", "none")
        .style("cursor", "pointer")
        .datum(goal)

      // ── Hover: glow the hovered goal, dim everything else ──
      hitTarget.on("mousemove", (event) => {
        const [mx, my] = d3.pointer(event, self.svg.node())
        const hitGoal = self.findGoalAtPoint(mx, my)

        if (hitGoal) {
          if (self._hoveredGoalId !== hitGoal.id) {
            self._hoveredGoalId = hitGoal.id

            // Dim all bricks, then brighten + glow the hovered ones
            self.brickLayer.selectAll(".brick")
              .transition().duration(150)
              .style("opacity", d => d.goalId === hitGoal.id ? 1 : 0.3)
              .style("filter", d => d.goalId === hitGoal.id ? "url(#brick-glow)" : null)

            // Dim/show highlights
            self.brickLayer.selectAll(".brick-highlight")
              .transition().duration(150)
              .style("opacity", d => d.goalId === hitGoal.id ? 1 : 0.3)

            // Dim/show labels
            self.labelLayer.selectAll(".label-title, .label-mpd")
              .transition().duration(150)
              .style("opacity", function() {
                const goalId = d3.select(this).datum()?.goalId
                return goalId === hitGoal.id ? 1 : 0.25
              })

            self.tooltip.html(hitGoal._tooltipHtml).classed("hidden", false)
            self.svgElement.style("cursor", "pointer")
          }
          // Tooltip position
          const rect = self.element.getBoundingClientRect()
          self.tooltip
            .style("left", `${event.clientX - rect.left + 15}px`)
            .style("top", `${event.clientY - rect.top - 10}px`)
        } else {
          self.clearHover()
        }
      })

      hitTarget.on("mouseleave", () => {
        self.clearHover()
      })

      // ── Click to navigate (checks ALL goals' bricks) ──
      hitTarget.on("click", (event) => {
        if (event.defaultPrevented) return
        const [mx, my] = d3.pointer(event, self.svg.node())
        const hitGoal = self.findGoalAtPoint(mx, my)
        if (hitGoal) {
          window.location.href = `/reading_goals/${hitGoal.id}`
        }
      })
    })
  }

  clearHover() {
    if (this._hoveredGoalId) {
      this._hoveredGoalId = null

      // Restore all bricks
      this.brickLayer.selectAll(".brick")
        .transition().duration(200)
        .style("opacity", 1)
        .style("filter", null)

      this.brickLayer.selectAll(".brick-highlight")
        .transition().duration(200)
        .style("opacity", 1)

      this.labelLayer.selectAll(".label-title, .label-mpd")
        .transition().duration(200)
        .style("opacity", 1)

      this.svgElement.style("cursor", "grab")
    }
    this.tooltip.classed("hidden", true)
  }

  // ── Hit testing ─────────────────────────────────────────────────

  findGoalAtPoint(mx, my) {
    const gap = 1.5
    // Check bricks in reverse order (topmost visually = last appended)
    for (let i = this.currentBricks.length - 1; i >= 0; i--) {
      const b = this.currentBricks[i]
      const bx = this.xScale(b.date) + gap / 2
      const by = this.yScale(b.yOffset + b.minutes) + gap / 2
      const bw = Math.max(this.xScale(b.nextDate) - this.xScale(b.date) - gap, 1)
      const bh = Math.max(this.yScale(b.yOffset) - this.yScale(b.yOffset + b.minutes) - gap, 1)
      if (mx >= bx && mx <= bx + bw && my >= by && my <= by + bh) {
        return this.goals.find(g => g.id === b.goalId)
      }
    }
    return null
  }

  // ── Legend ────────────────────────────────────────────────────────

  renderLegend(goals) {
    const legend = d3.select(this.element)
      .append("div")
      .attr("class", "flex flex-wrap gap-3 mt-4 justify-center text-sm")

    legend.selectAll(".legend-item")
      .data(goals)
      .enter()
      .append("div")
      .attr("class", "legend-item flex items-center gap-2")
      .html(d => `
        <span class="w-3 h-3 rounded" style="background-color: ${d.color}"></span>
        <span class="text-gray-600">${d.title}</span>
        ${!d.uses_actual_data ? '<span class="text-gray-400 text-xs">(est.)</span>' : ''}
      `)

    // Unowned legend entry
    if (goals.some(g => g._isUnowned)) {
      legend.append("div")
        .attr("class", "legend-item flex items-center gap-2")
        .html(`
          <span class="w-3 h-3 rounded border-2 border-dashed" style="border-color: #f59e0b"></span>
          <span class="text-gray-600">Not yet owned</span>
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
