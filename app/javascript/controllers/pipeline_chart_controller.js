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
          todayProgress = g.today_actual_minutes || 0
          // Total height stays at the planned daily share so today's column
          // matches future columns. The dark progress overlay shows how much
          // of that planned time has been completed.
          minutes = Math.max(g.minutes_per_day, todayProgress)
          todayProgress = Math.min(todayProgress, minutes)
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
    this.renderBricks(bricks, {})
    const labels = this.computeLabels(bricks, this.goals)
    this.renderLabels(labels, {})

    this.renderOverlays()

    if (!this.compactValue) {
      this.renderLegend(this.goals)
    }
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
    this.svg = d3.select(this.element)
      .append("svg")
      .attr("width", this.width + this.margin.left + this.margin.right)
      .attr("height", this.chartHeight + this.margin.top + this.margin.bottom)
      .append("g")
      .attr("transform", `translate(${this.margin.left},${this.margin.top})`)

    // Create layers
    this.gridLayer = this.svg.append("g").attr("class", "layer-grid")
    this.brickLayer = this.svg.append("g").attr("class", "layer-bricks")
    this.labelLayer = this.svg.append("g").attr("class", "layer-labels")
    this.overlayLayer = this.svg.append("g").attr("class", "layer-overlays")

    // Apply group-level drop shadow to brick layer
    this.brickLayer.style("filter", "drop-shadow(0 1px 2px rgba(0,0,0,0.15))")

    // Tooltip (DOM element, not SVG)
    this.tooltip = d3.select(this.element)
      .append("div")
      .attr("class", "absolute hidden bg-gray-900 text-white text-sm px-3 py-2 rounded-lg shadow-lg pointer-events-none z-50 max-w-xs")
      .style("transition", "opacity 0.15s")
  }

  renderDefs() {
    const defs = this.svg.append("defs")

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
          .attr("stop-color", d3.color(base).brighter(0.25))
          .attr("stop-opacity", opacity)
        grad.append("stop")
          .attr("offset", "100%")
          .attr("stop-color", d3.color(base).darker(0.2))
          .attr("stop-opacity", opacity)
      })
    })
  }

  renderGrid() {
    const g = this.gridLayer

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
      .style("stroke", "#e8e8e8")
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
      .style("stroke", "#e5e7eb")
      .style("stroke-dasharray", "2,2")

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
      .style("fill", "#f3f4f6")
      .style("opacity", 0.6)

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
      .style("fill", "#6b7280")

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
      .style("fill", "#6b7280")

    // Y axis label
    if (!this.compactValue) {
      g.append("text")
        .attr("transform", "rotate(-90)")
        .attr("y", -this.margin.left + 14)
        .attr("x", -this.chartHeight / 2)
        .attr("text-anchor", "middle")
        .style("fill", "#9ca3af")
        .style("font-size", "12px")
        .text("minutes / day")
    }

    // Today marker
    const todayDate = new Date()
    if (todayDate >= this.startDate && todayDate <= this.endDate) {
      g.append("line")
        .attr("x1", this.xScale(todayDate))
        .attr("x2", this.xScale(todayDate))
        .attr("y1", 0)
        .attr("y2", this.chartHeight)
        .style("stroke", "#ef4444")
        .style("stroke-width", 2)
        .style("stroke-dasharray", "4,4")

      g.append("text")
        .attr("x", this.xScale(todayDate))
        .attr("y", -8)
        .attr("text-anchor", "middle")
        .style("fill", "#ef4444")
        .style("font-size", "11px")
        .style("font-weight", "500")
        .text("Today")
    }
  }

  renderBricks(bricks, opts = {}) {
    const gap = 1
    const t = opts.transition
      ? d3.transition().duration(opts.duration || 80).ease(d3.easeCubicOut)
      : null

    // ── Main brick rects ──
    const join = this.brickLayer.selectAll(".brick")
      .data(bricks, d => d.key)

    join.exit().remove()

    const enter = join.enter()
      .append("rect")
      .attr("class", "brick")
      .attr("rx", 2)
      .attr("ry", 2)

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

    // Position enter elements immediately (no transition from 0,0)
    applyAttrs(enter)

    if (t) {
      applyAttrs(join.transition(t))
    } else {
      applyAttrs(join)
    }

    // ── Today progress overlay bricks ──
    const todayBricks = bricks.filter(b => b.isToday && b.todayProgress > 0)

    const progressJoin = this.brickLayer.selectAll(".brick-today-progress")
      .data(todayBricks, d => d.key + "-progress")

    progressJoin.exit().remove()

    const progressEnter = progressJoin.enter()
      .append("rect")
      .attr("class", "brick-today-progress")
      .attr("rx", 2)
      .attr("ry", 2)

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

    applyProgress(progressEnter)

    if (t) {
      applyProgress(progressJoin.transition(t))
    } else {
      applyProgress(progressJoin)
    }

    // ── Highlight lines (top edge bevel) ──
    const highlightJoin = this.brickLayer.selectAll(".brick-highlight")
      .data(bricks, d => d.key + "-hl")

    highlightJoin.exit().remove()

    const hlEnter = highlightJoin.enter()
      .append("line")
      .attr("class", "brick-highlight")
      .style("stroke", "rgba(255,255,255,0.3)")
      .style("stroke-width", 0.5)
      .style("pointer-events", "none")

    const applyHighlight = (sel) => {
      sel
        .attr("x1", d => this.xScale(d.date) + gap / 2 + 1)
        .attr("x2", d => this.xScale(d.nextDate) - gap / 2 - 1)
        .attr("y1", d => this.yScale(d.yOffset + d.minutes) + gap / 2 + 0.5)
        .attr("y2", d => this.yScale(d.yOffset + d.minutes) + gap / 2 + 0.5)
    }

    applyHighlight(hlEnter)

    if (t) {
      applyHighlight(highlightJoin.transition(t))
    } else {
      applyHighlight(highlightJoin)
    }

    // ── Queued goal dashed borders ──
    // ── Unowned goal amber dotted borders ──
    const unownedBricks = bricks.filter(b => b.isUnowned)
    const unownedJoin = this.brickLayer.selectAll(".brick-unowned-border")
      .data(unownedBricks, d => d.key + "-ub")

    unownedJoin.exit().remove()

    const ubEnter = unownedJoin.enter()
      .append("rect")
      .attr("class", "brick-unowned-border")
      .attr("rx", 2)
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
    if (t) { applyUnowned(unownedJoin.transition(t)) } else { applyUnowned(unownedJoin) }

    // ── Queued goal dashed borders ──
    const queuedBricks = bricks.filter(b => b.isQueued)
    const queuedJoin = this.brickLayer.selectAll(".brick-queued-border")
      .data(queuedBricks, d => d.key + "-qb")

    queuedJoin.exit().remove()

    const qbEnter = queuedJoin.enter()
      .append("rect")
      .attr("class", "brick-queued-border")
      .attr("rx", 2)
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
    if (t) { applyQueued(queuedJoin.transition(t)) } else { applyQueued(queuedJoin) }
  }

  renderLabels(labels, opts = {}) {
    const t = opts.transition
      ? d3.transition().duration(opts.duration || 80).ease(d3.easeCubicOut)
      : null

    // Title labels
    const titleJoin = this.labelLayer.selectAll(".label-title")
      .data(labels.filter(l => l.width >= 60 && l.height >= 16), d => d.goalId + "-title")

    titleJoin.exit().remove()

    const titleEnter = titleJoin.enter()
      .append("text")
      .attr("class", "label-title")
      .style("fill", "#fff")
      .style("font-weight", "600")
      .style("text-shadow", "0 1px 2px rgba(0,0,0,0.4)")
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

    applyTitle(titleEnter)

    if (t) {
      applyTitle(titleJoin.transition(t))
    } else {
      applyTitle(titleJoin)
    }

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
        .style("text-shadow", "0 1px 2px rgba(0,0,0,0.4)")
        .style("pointer-events", "none")
        .attr("dy", "0.35em")

      const applyMpd = (sel) => {
        sel
          .attr("x", d => d.xEnd)
          .attr("y", d => d.y)
          .text(d => `${d.minutesPerDay}m/day`)
      }

      applyMpd(mpdEnter)

      if (t) {
        applyMpd(mpdJoin.transition(t))
      } else {
        applyMpd(mpdJoin)
      }
    }

    // Estimate indicators (dashed border on widest run for goals without actual data)
    const estimateLabels = labels.filter(l => !l.usesActualData && l.width > 20 && l.height > 4)
    const estJoin = this.labelLayer.selectAll(".estimate-indicator")
      .data(estimateLabels, d => d.goalId + "-est")

    estJoin.exit().remove()

    const estEnter = estJoin.enter()
      .append("rect")
      .attr("class", "estimate-indicator")
      .attr("rx", 2)
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

    if (t) {
      applyEst(estJoin.transition(t))
    } else {
      applyEst(estJoin)
    }
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

      goal._tooltipHtml = `
        <div class="font-semibold mb-1">${goal.title}</div>
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
        .attr("class", "overlay-hit cursor-pointer")
        .attr("x", minX)
        .attr("y", minY)
        .attr("width", maxX - minX)
        .attr("height", maxY - minY)
        .style("fill", "transparent")
        .style("stroke", "none")
        .datum(goal)

      // ── Hover tooltip (checks ALL goals' bricks, not just this overlay's) ──
      hitTarget.on("mousemove", (event) => {
        const [mx, my] = d3.pointer(event, self.svg.node())
        const hitGoal = self.findGoalAtPoint(mx, my)

        if (hitGoal) {
          if (self._hoveredGoalId !== hitGoal.id) {
            // Clear previous highlight
            if (self._hoveredGoalId) {
              self.brickLayer.selectAll(".brick")
                .filter(d => d.goalId === self._hoveredGoalId)
                .style("filter", null)
            }
            self._hoveredGoalId = hitGoal.id
            self.brickLayer.selectAll(".brick")
              .filter(d => d.goalId === hitGoal.id)
              .style("filter", "brightness(1.1)")
            self.tooltip.html(hitGoal._tooltipHtml).classed("hidden", false)
          }
          self.tooltip
            .style("left", `${event.offsetX + 15}px`)
            .style("top", `${event.offsetY - 10}px`)
        } else {
          if (self._hoveredGoalId) {
            self.brickLayer.selectAll(".brick")
              .filter(d => d.goalId === self._hoveredGoalId)
              .style("filter", null)
            self._hoveredGoalId = null
          }
          self.tooltip.classed("hidden", true)
        }
      })

      hitTarget.on("mouseleave", () => {
        if (self._hoveredGoalId) {
          self.brickLayer.selectAll(".brick")
            .filter(d => d.goalId === self._hoveredGoalId)
            .style("filter", null)
          self._hoveredGoalId = null
        }
        self.tooltip.classed("hidden", true)
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

  // ── Hit testing ─────────────────────────────────────────────────

  findGoalAtPoint(mx, my) {
    const gap = 1
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
