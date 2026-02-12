import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"

// Connects to data-controller="pipeline-chart"
export default class extends Controller {
  static values = {
    url: String,
    compact: { type: Boolean, default: false },
    editMode: { type: Boolean, default: false }
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
  }

  toggleEditMode() {
    this.editModeValue = !this.editModeValue
    this.render()
  }

  disconnect() {
    window.removeEventListener("resize", this.resizeHandler)
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

  // Compute interlocking brick segments for all goals.
  // Past days use actual reading time, future days use planned time.
  // At every transition point, restack the active books so blocks
  // drop down into gaps.
  computeSegments(goals) {
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    const todayTime = today.getTime()
    const dayMs = 86400000
    // Format today as YYYY-MM-DD for reliable comparison
    const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`

    // Collect all unique transition dates
    const dateSet = new Set()
    goals.forEach(g => {
      dateSet.add(g.startDate.getTime())
      dateSet.add(g.endDate.getTime())
    })

    // Add today as a key transition (past vs future boundary)
    dateSet.add(todayTime)

    // Add daily boundaries for PAST days (so each past day is its own segment)
    // This allows us to show actual reading time per day
    const earliest = Math.min(...goals.map(g => g.startDate.getTime()))
    let day = new Date(earliest)
    while (day.getTime() < todayTime) {
      dateSet.add(day.getTime())
      day = new Date(day.getTime() + dayMs)
    }

    // Add weekday/weekend boundaries for goals that exclude weekends
    const hasWeekendExclusion = goals.some(g => !g.include_weekends)
    if (hasWeekendExclusion) {
      const latest = Math.max(...goals.map(g => g.endDate.getTime()))
      day = new Date(earliest)
      while (day.getTime() <= latest) {
        const dow = day.getDay()
        if (dow === 6 || dow === 1) {
          dateSet.add(day.getTime())
        }
        day = new Date(day.getTime() + dayMs)
      }
    }

    const transitions = Array.from(dateSet).sort((a, b) => a - b)

    // Helper to get actual minutes for a goal on a specific date
    const getActualMinutes = (goal, dateStr) => {
      if (!goal.actual_minutes_by_date) return 0
      return goal.actual_minutes_by_date[dateStr] || 0
    }

    // For each interval, stack the active goals
    const segmentsByGoal = new Map()
    goals.forEach(g => segmentsByGoal.set(g.id, []))

    for (let i = 0; i < transitions.length - 1; i++) {
      const segStart = transitions[i]
      const segEnd = transitions[i + 1]
      const segDay = new Date(segStart)
      const isWeekend = segDay.getDay() === 0 || segDay.getDay() === 6
      const isPast = segStart < todayTime
      const dateStr = segDay.toISOString().split('T')[0]

      // Which goals are active during this interval?
      const active = goals.filter(g => {
        if (g.startDate.getTime() > segStart || g.endDate.getTime() < segEnd) return false
        if (isWeekend && !g.include_weekends) return false
        return true
      })

      // Determine if this is today
      const isToday = segStart === todayTime

      // For past days, filter to only goals that had actual reading
      // For future days (including today), include all active goals
      const goalsWithHeight = active.map(g => {
        let minutes
        let todayProgress = 0
        if (isPast) {
          // Use actual reading time for past days
          minutes = getActualMinutes(g, dateStr)
        } else if (isToday) {
          // Today: height = actual reading time + estimated remaining time
          todayProgress = g.today_actual_minutes || 0
          const remaining = g.today_remaining_minutes || 0
          minutes = todayProgress + remaining
        } else {
          // Use planned time for future days
          minutes = g.minutes_per_day
        }
        return { goal: g, minutes, isPast, isToday, todayProgress }
      }).filter(item => item.minutes > 0) // Only include if there's height to show

      // Stack them: longest duration on bottom (already sorted by duration)
      let yOffset = 0
      goalsWithHeight.forEach(({ goal, minutes, isPast, isToday, todayProgress }) => {
        segmentsByGoal.get(goal.id).push({
          startDate: new Date(segStart),
          endDate: new Date(segEnd),
          yOffset: yOffset,
          minutes_per_day: minutes,
          isPast: isPast,
          isToday: isToday,
          todayProgress: todayProgress
        })
        yOffset += minutes
      })
    }

    // Compute total Y extent (peak stack height)
    let maxY = 0
    segmentsByGoal.forEach(segments => {
      segments.forEach(s => {
        maxY = Math.max(maxY, s.yOffset + s.minutes_per_day)
      })
    })

    // Also consider planned minutes_per_day for Y scale (so future doesn't clip)
    goals.forEach(g => {
      maxY = Math.max(maxY, g.minutes_per_day)
    })

    // Merge adjacent segments with same properties (reduces path complexity)
    // Only merge if: same yOffset, same minutes, same isPast status, contiguous
    segmentsByGoal.forEach((segments, goalId) => {
      if (segments.length <= 1) return
      const merged = [segments[0]]
      for (let i = 1; i < segments.length; i++) {
        const prev = merged[merged.length - 1]
        const curr = segments[i]
        if (curr.yOffset === prev.yOffset &&
            curr.minutes_per_day === prev.minutes_per_day &&
            curr.isPast === prev.isPast &&
            curr.startDate.getTime() === prev.endDate.getTime()) {
          prev.endDate = curr.endDate
        } else {
          merged.push(curr)
        }
      }
      segmentsByGoal.set(goalId, merged)
    })

    return { segmentsByGoal, maxY }
  }

  // Group consecutive segments into runs (no time gap between them)
  groupIntoRuns(segments) {
    if (segments.length === 0) return []
    const runs = []
    let currentRun = [segments[0]]
    for (let i = 1; i < segments.length; i++) {
      if (segments[i].startDate.getTime() === currentRun[currentRun.length - 1].endDate.getTime()) {
        currentRun.push(segments[i])
      } else {
        runs.push(currentRun)
        currentRun = [segments[i]]
      }
    }
    runs.push(currentRun)
    return runs
  }

  // Build SVG path string from runs of segments
  buildPathFromRuns(runs, xScale, yScale) {
    let pathD = ""
    runs.forEach(run => {
      // Trace top edge left-to-right
      pathD += `M ${xScale(run[0].startDate)} ${yScale(run[0].yOffset + run[0].minutes_per_day)}`
      for (let i = 0; i < run.length; i++) {
        const seg = run[i]
        const top = yScale(seg.yOffset + seg.minutes_per_day)
        if (i > 0) pathD += ` V ${top}`
        pathD += ` H ${xScale(seg.endDate)}`
      }
      // Trace bottom edge right-to-left
      for (let i = run.length - 1; i >= 0; i--) {
        const seg = run[i]
        const bottom = yScale(seg.yOffset)
        pathD += ` V ${bottom}`
        if (i > 0) pathD += ` H ${xScale(seg.startDate)}`
      }
      pathD += ` H ${xScale(run[0].startDate)} Z`
    })
    return pathD
  }

  render() {
    if (!this.chartData || !this.chartData.goals.length) {
      this.element.innerHTML = `
        <div class="flex items-center justify-center h-48 text-gray-500">
          <p>Create a reading goal to see your pipeline.</p>
        </div>
      `
      return
    }

    this.element.innerHTML = ""

    const containerWidth = this.element.clientWidth
    const width = Math.max(containerWidth, this.minWidth) - this.margin.left - this.margin.right

    // Parse dates and filter valid goals
    // Note: endDate is set to the day AFTER target_completion_date so the goal
    // is active on its last day (segment dates are [start, end) intervals)
    let goals = this.chartData.goals
      .filter(g => g.start_date && g.end_date && g.minutes_per_day > 0)
      .map(g => ({
        ...g,
        startDate: new Date(g.start_date + "T00:00:00"),
        endDate: d3.timeDay.offset(new Date(g.end_date + "T00:00:00"), 1)
      }))

    if (goals.length === 0) {
      this.element.innerHTML = `
        <div class="flex items-center justify-center h-48 text-gray-500">
          <p>Set dates on your reading goals to see them in the pipeline.</p>
        </div>
      `
      return
    }

    // Sort by duration descending (longest on bottom = Breakout style)
    goals.sort((a, b) => b.duration_days - a.duration_days)

    // Assign colors
    goals.forEach((g, i) => {
      g.color = this.constructor.BLOCK_COLORS[i % this.constructor.BLOCK_COLORS.length]
    })

    // Compute interlocking brick segments
    const { segmentsByGoal, maxY } = this.computeSegments(goals)
    const totalMinutes = maxY || 1

    // Dynamic chart height based on content
    const minChartHeight = this.compactValue ? 150 : 250
    const maxChartHeight = this.compactValue ? 250 : 500
    const chartHeight = Math.min(Math.max(totalMinutes * 2.5, minChartHeight), maxChartHeight)

    // Date range with padding
    const minDate = d3.min(goals, d => d.startDate)
    const maxDate = d3.max(goals, d => d.endDate)
    const daysPadding = 3
    const startDate = d3.timeDay.offset(minDate, -daysPadding)
    const endDate = d3.timeDay.offset(maxDate, daysPadding)

    // X scale (time/days)
    const xScale = d3.scaleTime()
      .domain([startDate, endDate])
      .range([0, width])

    // Y scale (minutes — 0 at bottom, totalMinutes at top)
    const yScale = d3.scaleLinear()
      .domain([0, totalMinutes])
      .range([chartHeight, 0])

    // Edit mode toggle button
    if (!this.compactValue) {
      const editToggle = d3.select(this.element)
        .append("div")
        .attr("class", "absolute top-2 right-2 z-10")

      editToggle.append("button")
        .attr("type", "button")
        .attr("class", () => this.editModeValue
          ? "inline-flex items-center gap-1.5 rounded-md bg-amber-100 px-2.5 py-1.5 text-sm font-medium text-amber-700 hover:bg-amber-200 transition-colors ring-2 ring-amber-300"
          : "inline-flex items-center gap-1.5 rounded-md bg-gray-100 px-2.5 py-1.5 text-sm font-medium text-gray-600 hover:bg-gray-200 transition-colors"
        )
        .html(() => this.editModeValue
          ? `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/></svg> Editing`
          : `<svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.232 5.232l3.536 3.536m-2.036-5.036a2.5 2.5 0 113.536 3.536L6.5 21.036H3v-3.572L16.732 3.732z"/></svg> Edit`
        )
        .on("click", () => this.toggleEditMode())

      // Show edit mode hint when active
      if (this.editModeValue) {
        editToggle.append("div")
          .attr("class", "mt-1 text-xs text-amber-600")
          .text("Drag to move, resize right edge")
      }
    }

    // Create SVG
    const svg = d3.select(this.element)
      .append("svg")
      .attr("width", width + this.margin.left + this.margin.right)
      .attr("height", chartHeight + this.margin.top + this.margin.bottom)
      .append("g")
      .attr("transform", `translate(${this.margin.left},${this.margin.top})`)

    // Grid lines (horizontal for minutes)
    const minuteTicks = this.niceMinuteTicks(totalMinutes)
    svg.append("g")
      .attr("class", "grid")
      .selectAll("line")
      .data(minuteTicks)
      .enter()
      .append("line")
      .attr("x1", 0)
      .attr("x2", width)
      .attr("y1", d => yScale(d))
      .attr("y2", d => yScale(d))
      .style("stroke", "#e5e7eb")
      .style("stroke-dasharray", "2,2")

    // Grid lines (vertical for weeks)
    svg.append("g")
      .attr("class", "grid")
      .attr("transform", `translate(0,${chartHeight})`)
      .call(
        d3.axisBottom(xScale)
          .ticks(d3.timeWeek.every(1))
          .tickSize(-chartHeight)
          .tickFormat("")
      )
      .selectAll("line")
      .style("stroke", "#f3f4f6")

    // Weekend shading (if any goal excludes weekends)
    const hasWeekendExclusion = goals.some(g => !g.include_weekends)
    if (hasWeekendExclusion) {
      const weekendDays = []
      let day = d3.timeDay.floor(startDate)
      while (day <= endDate) {
        if (day.getDay() === 0 || day.getDay() === 6) {
          weekendDays.push(new Date(day))
        }
        day = d3.timeDay.offset(day, 1)
      }

      svg.append("g")
        .attr("class", "weekend-shading")
        .selectAll("rect")
        .data(weekendDays)
        .enter()
        .append("rect")
        .attr("x", d => xScale(d))
        .attr("y", 0)
        .attr("width", d => xScale(d3.timeDay.offset(d, 1)) - xScale(d))
        .attr("height", chartHeight)
        .style("fill", "#f3f4f6")
        .style("opacity", 0.6)
    }

    // X axis
    const xAxis = d3.axisBottom(xScale)
      .ticks(d3.timeWeek.every(1))
      .tickFormat(d3.timeFormat("%b %d"))

    svg.append("g")
      .attr("class", "x-axis")
      .attr("transform", `translate(0,${chartHeight})`)
      .call(xAxis)
      .selectAll("text")
      .style("font-size", "11px")
      .style("fill", "#6b7280")

    // Y axis (minutes per day)
    const yAxis = d3.axisLeft(yScale)
      .tickValues(minuteTicks)
      .tickFormat(d => `${d}m`)

    svg.append("g")
      .attr("class", "y-axis")
      .call(yAxis)
      .selectAll("text")
      .style("font-size", "11px")
      .style("fill", "#6b7280")

    // Y axis label
    if (!this.compactValue) {
      svg.append("text")
        .attr("transform", "rotate(-90)")
        .attr("y", -this.margin.left + 14)
        .attr("x", -chartHeight / 2)
        .attr("text-anchor", "middle")
        .style("fill", "#9ca3af")
        .style("font-size", "12px")
        .text("minutes / day")
    }

    // Today marker
    const today = new Date()
    if (today >= startDate && today <= endDate) {
      svg.append("line")
        .attr("x1", xScale(today))
        .attr("x2", xScale(today))
        .attr("y1", 0)
        .attr("y2", chartHeight)
        .style("stroke", "#ef4444")
        .style("stroke-width", 2)
        .style("stroke-dasharray", "4,4")

      svg.append("text")
        .attr("x", xScale(today))
        .attr("y", -8)
        .attr("text-anchor", "middle")
        .style("fill", "#ef4444")
        .style("font-size", "11px")
        .style("font-weight", "500")
        .text("Today")
    }

    // Tooltip
    const tooltip = d3.select(this.element)
      .append("div")
      .attr("class", "absolute hidden bg-gray-900 text-white text-sm px-3 py-2 rounded-lg shadow-lg pointer-events-none z-50 max-w-xs")
      .style("transition", "opacity 0.15s")

    // Draw interlocking brick segments for each goal
    const self = this
    goals.forEach(goal => {
      const segments = segmentsByGoal.get(goal.id)
      if (!segments || segments.length === 0) return

      const blockGroup = svg.append("g")
        .attr("class", `pipeline-block ${this.editModeValue ? "cursor-move" : "cursor-pointer"}`)
        .datum(goal)

      // Group consecutive segments into runs (no time gap between them)
      // and draw each run as a single SVG path tracing the staircase outline.
      const runs = []
      let currentRun = [segments[0]]
      for (let i = 1; i < segments.length; i++) {
        if (segments[i].startDate.getTime() === currentRun[currentRun.length - 1].endDate.getTime()) {
          currentRun.push(segments[i])
        } else {
          runs.push(currentRun)
          currentRun = [segments[i]]
        }
      }
      runs.push(currentRun)

      // Build a single path string for all runs
      let pathD = ""
      runs.forEach(run => {
        // Trace top edge left-to-right
        pathD += `M ${xScale(run[0].startDate)} ${yScale(run[0].yOffset + run[0].minutes_per_day)}`
        for (let i = 0; i < run.length; i++) {
          const seg = run[i]
          const top = yScale(seg.yOffset + seg.minutes_per_day)
          if (i > 0) pathD += ` V ${top}`
          pathD += ` H ${xScale(seg.endDate)}`
        }
        // Trace bottom edge right-to-left
        for (let i = run.length - 1; i >= 0; i--) {
          const seg = run[i]
          const bottom = yScale(seg.yOffset)
          pathD += ` V ${bottom}`
          if (i > 0) pathD += ` H ${xScale(seg.startDate)}`
        }
        pathD += ` H ${xScale(run[0].startDate)} Z`
      })

      // Separate past, today, and future segments for different styling
      const pastSegments = segments.filter(s => s.isPast)
      const todaySegment = segments.find(s => s.isToday)
      const futureSegments = segments.filter(s => !s.isPast && !s.isToday)

      // Build path for past segments (actual reading time) - slightly darker
      if (pastSegments.length > 0) {
        const pastRuns = this.groupIntoRuns(pastSegments)
        const pastPathD = this.buildPathFromRuns(pastRuns, xScale, yScale)

        blockGroup.append("path")
          .attr("class", "block-fill block-past")
          .attr("d", pastPathD)
          .style("fill", d3.color(goal.color).darker(0.3))
          .style("opacity", 0.95)
      }

      // Build path for today's segment (planned time as background)
      if (todaySegment) {
        const todayRuns = [[todaySegment]]
        const todayPathD = this.buildPathFromRuns(todayRuns, xScale, yScale)

        // Draw planned height as lighter background
        blockGroup.append("path")
          .attr("class", "block-fill block-today-planned")
          .attr("d", todayPathD)
          .style("fill", goal.color)
          .style("opacity", 0.85)

        // Draw actual progress filling up from the bottom
        // Only show progress on TODAY's column, not the entire segment
        if (todaySegment.todayProgress > 0) {
          const progressHeight = Math.min(todaySegment.todayProgress, todaySegment.minutes_per_day)
          const progressTop = yScale(todaySegment.yOffset + progressHeight)
          const progressBottom = yScale(todaySegment.yOffset)

          // Clip to just today's single day column
          const todayColumnEnd = d3.timeDay.offset(todaySegment.startDate, 1)

          blockGroup.append("rect")
            .attr("class", "block-fill block-today-progress")
            .attr("x", xScale(todaySegment.startDate))
            .attr("y", progressTop)
            .attr("width", xScale(todayColumnEnd) - xScale(todaySegment.startDate))
            .attr("height", progressBottom - progressTop)
            .style("fill", d3.color(goal.color).darker(0.3))
            .style("opacity", 0.95)
        }
      }

      // Build path for future segments (planned time)
      if (futureSegments.length > 0) {
        const futureRuns = this.groupIntoRuns(futureSegments)
        const futurePathD = this.buildPathFromRuns(futureRuns, xScale, yScale)

        blockGroup.append("path")
          .attr("class", "block-fill block-future")
          .attr("d", futurePathD)
          .style("fill", goal.color)
          .style("opacity", 0.85)
      }

      // Combined path for interactions (invisible, covers both)
      blockGroup.append("path")
        .attr("class", "block-fill-interactive")
        .attr("d", pathD)
        .style("fill", "transparent")
        .style("stroke", "none")

      // Progress overlay — clip the same shape to the progress range
      const progressEndDate = new Date(goal.startDate.getTime() + (goal.endDate.getTime() - goal.startDate.getTime()) * (goal.progress / 100))
      if (goal.progress > 0) {
        const clipId = `clip-progress-${goal.id}`
        svg.append("defs").append("clipPath").attr("id", clipId)
          .append("rect")
          .attr("x", xScale(goal.startDate))
          .attr("y", 0)
          .attr("width", xScale(progressEndDate) - xScale(goal.startDate))
          .attr("height", chartHeight)

        blockGroup.append("path")
          .attr("class", "block-progress")
          .attr("d", pathD)
          .attr("clip-path", `url(#${clipId})`)
          .style("fill", d3.color(goal.color).darker(0.5))
          .style("opacity", 0.4)
      }

      // Estimate indicator (dashed inner border on widest segment)
      if (!goal.uses_actual_data) {
        const widest = segments.reduce((a, b) =>
          (xScale(b.endDate) - xScale(b.startDate)) > (xScale(a.endDate) - xScale(a.startDate)) ? b : a
        )
        const wx = xScale(widest.startDate) + 1
        const wy = yScale(widest.yOffset + widest.minutes_per_day) + 1
        const ww = Math.max(xScale(widest.endDate) - xScale(widest.startDate) - 2, 4)
        const wh = Math.max(yScale(widest.yOffset) - yScale(widest.yOffset + widest.minutes_per_day) - 2, 1)

        blockGroup.append("rect")
          .attr("x", wx).attr("y", wy)
          .attr("width", ww).attr("height", wh)
          .attr("rx", 2)
          .style("fill", "none")
          .style("stroke", "rgba(255,255,255,0.3)")
          .style("stroke-width", 1)
          .style("stroke-dasharray", "3,3")
      }

      // Book title label — placed on the widest merged segment
      const widestSeg = segments.reduce((a, b) =>
        (xScale(b.endDate) - xScale(b.startDate)) > (xScale(a.endDate) - xScale(a.startDate)) ? b : a
      )
      const labelWidth = xScale(widestSeg.endDate) - xScale(widestSeg.startDate)
      const labelHeight = yScale(widestSeg.yOffset) - yScale(widestSeg.yOffset + widestSeg.minutes_per_day)

      if (labelWidth >= 60 && labelHeight >= 18) {
        const maxChars = Math.floor((labelWidth - 16) / 7)
        const title = goal.title.length > maxChars ? goal.title.substring(0, maxChars - 1) + "\u2026" : goal.title

        blockGroup.append("text")
          .attr("x", xScale(widestSeg.startDate) + 8)
          .attr("y", yScale(widestSeg.yOffset + widestSeg.minutes_per_day) + labelHeight / 2)
          .attr("dy", "0.35em")
          .style("fill", "#fff")
          .style("font-size", labelHeight >= 28 ? "12px" : "10px")
          .style("font-weight", "600")
          .style("text-shadow", "0 1px 2px rgba(0,0,0,0.3)")
          .style("pointer-events", "none")
          .text(title)
      }

      // Minutes/day label on widest segment
      if (!this.compactValue && labelHeight >= 18 && labelWidth >= 80) {
        blockGroup.append("text")
          .attr("x", xScale(widestSeg.endDate) - 8)
          .attr("y", yScale(widestSeg.yOffset + widestSeg.minutes_per_day) + labelHeight / 2)
          .attr("dy", "0.35em")
          .attr("text-anchor", "end")
          .style("fill", "rgba(255,255,255,0.8)")
          .style("font-size", "10px")
          .style("font-weight", "500")
          .style("text-shadow", "0 1px 2px rgba(0,0,0,0.3)")
          .style("pointer-events", "none")
          .text(`${goal.minutes_per_day}m/day`)
      }

      // Resize handle (right edge of the last segment) - only visible in edit mode
      const lastSeg = segments[segments.length - 1]
      if (this.editModeValue) {
        // Create resize tooltip
        const resizeTooltip = d3.select(this.element)
          .append("div")
          .attr("class", "resize-tooltip absolute hidden bg-gray-900 text-white text-sm px-3 py-2 rounded-lg shadow-xl pointer-events-none z-50 border border-gray-700")

        blockGroup.append("rect")
          .attr("class", "resize-handle")
          .attr("x", xScale(lastSeg.endDate) - 6)
          .attr("y", yScale(lastSeg.yOffset + lastSeg.minutes_per_day))
          .attr("width", 8)
          .attr("height", Math.max(yScale(lastSeg.yOffset) - yScale(lastSeg.yOffset + lastSeg.minutes_per_day), 2))
          .style("fill", "rgba(255,255,255,0.3)")
          .style("cursor", "ew-resize")
          .attr("rx", 2)
          .call(d3.drag()
            .on("start", function(event) {
              goal._resizeStartX = event.x
              goal._origEndDate = goal.endDate

              // Visual feedback
              d3.select(this)
                .style("fill", "rgba(255,255,255,0.7)")
                .style("width", "10px")

              // Show resize tooltip
              resizeTooltip
                .classed("hidden", false)
                .html(self.formatResizeTooltip(goal._origEndDate, 0))
            })
            .on("drag", function(event) {
              const dx = event.x - goal._resizeStartX
              const msPerPx = (endDate - startDate) / width
              const offsetMs = dx * msPerPx

              // Snap to day boundaries
              const dayMs = 86400000
              const snappedOffsetMs = Math.round(offsetMs / dayMs) * dayMs
              const newEnd = new Date(goal._origEndDate.getTime() + snappedOffsetMs)

              if (newEnd > goal.startDate) {
                goal.endDate = newEnd
                d3.select(this).attr("x", xScale(goal.endDate) - 6)

                // Calculate days changed
                const daysChanged = Math.round(snappedOffsetMs / dayMs)

                // Update tooltip
                resizeTooltip
                  .html(self.formatResizeTooltip(goal.endDate, daysChanged))
                  .style("left", `${event.sourceEvent.offsetX + 20}px`)
                  .style("top", `${event.sourceEvent.offsetY - 40}px`)
              }
            })
            .on("end", function() {
              d3.select(this)
                .style("fill", "rgba(255,255,255,0.3)")
                .style("width", "8px")

              resizeTooltip.classed("hidden", true)

              if (goal.endDate.getTime() !== goal._origEndDate.getTime()) {
                self.updateGoalDates(goal.id, goal.startDate, goal.endDate)
              }
            })
          )
      }

      // Drag to move entire block horizontally - only in edit mode
      if (this.editModeValue) {
        // Create drag tooltip element (hidden initially)
        const dragTooltip = d3.select(this.element)
          .append("div")
          .attr("class", "drag-tooltip absolute hidden bg-gray-900 text-white text-sm px-3 py-2 rounded-lg shadow-xl pointer-events-none z-50 border border-gray-700")
          .style("transition", "opacity 0.1s")

        blockGroup.call(d3.drag()
          .filter(function(event) {
            return !event.target.classList.contains("resize-handle")
          })
          .on("start", function(event) {
            goal._dragStartX = event.x
            goal._origStartDate = goal.startDate
            goal._origEndDate = goal.endDate

            // Determine if goal has past activity that locks the start
            goal._hasSessionHistory = goal.has_sessions && goal.earliest_session_date
            if (goal._hasSessionHistory) {
              goal._earliestSessionDate = new Date(goal.earliest_session_date + "T00:00:00")
              goal._latestSessionDate = new Date(goal.latest_session_date + "T00:00:00")
              // Lock point is the day after latest session (or today, whichever is later)
              const dayAfterLastSession = new Date(goal._latestSessionDate.getTime() + 86400000)
              goal._lockDate = new Date(Math.max(dayAfterLastSession.getTime(), today.getTime()))
              goal._isPostponeMode = goal._lockDate <= goal._origEndDate
            } else {
              goal._isPostponeMode = false
            }

            // Create ghost outline at original position
            const ghostGroup = svg.insert("g", ":first-child")
              .attr("class", "drag-ghost")
              .style("pointer-events", "none")

            ghostGroup.append("path")
              .attr("d", pathD)
              .style("fill", "none")
              .style("stroke", goal.color)
              .style("stroke-width", 2)
              .style("stroke-dasharray", "6,4")
              .style("opacity", 0.5)

            goal._ghostGroup = ghostGroup

            // If in postpone mode, highlight the locked portion
            if (goal._isPostponeMode) {
              goal._lockedGhost = svg.insert("g", ":first-child")
                .attr("class", "locked-ghost")
                .style("pointer-events", "none")

              // Draw locked indicator over past portion
              const lockedStart = xScale(goal._origStartDate)
              const lockedEnd = xScale(goal._lockDate)
              const lockedWidth = lockedEnd - lockedStart

              if (lockedWidth > 0) {
                goal._lockedGhost
                  .append("rect")
                  .attr("x", lockedStart)
                  .attr("y", 0)
                  .attr("width", lockedWidth)
                  .attr("height", chartHeight)
                  .style("fill", "rgba(34, 197, 94, 0.1)")
                  .style("stroke", "#22c55e")
                  .style("stroke-width", 1)
                  .style("stroke-dasharray", "4,4")

                goal._lockedGhost
                  .append("text")
                  .attr("x", lockedStart + lockedWidth / 2)
                  .attr("y", 12)
                  .attr("text-anchor", "middle")
                  .style("fill", "#22c55e")
                  .style("font-size", "10px")
                  .style("font-weight", "600")
                  .text("📌 Locked history")
              }
            }

            // Enhance dragging block appearance
            d3.select(this)
              .raise()
              .style("filter", "drop-shadow(0 4px 12px rgba(0,0,0,0.3))")
              .style("transform", "scale(1.02)")
              .style("transform-origin", "center")

            d3.select(this).selectAll(".block-fill")
              .style("opacity", 1)
              .style("stroke", "#fff")
              .style("stroke-width", 2)

            // Show drag tooltip
            const mode = goal._isPostponeMode ? "postpone" : "move"
            dragTooltip
              .classed("hidden", false)
              .html(self.formatDragTooltip(goal._origStartDate, goal._origEndDate, 0, null, mode))
          })
          .on("drag", function(event) {
            const dx = event.x - goal._dragStartX
            const msPerPx = (endDate - startDate) / width
            const offsetMs = dx * msPerPx

            // Snap to day boundaries
            const dayMs = 86400000
            const snappedOffsetMs = Math.round(offsetMs / dayMs) * dayMs
            const daysShifted = Math.round(snappedOffsetMs / dayMs)

            if (goal._isPostponeMode) {
              // Postpone mode: start stays anchored, only end moves
              // Calculate new future start (where remaining work will begin)
              const origDuration = goal._origEndDate.getTime() - goal._lockDate.getTime()
              goal._newFutureStart = new Date(goal._lockDate.getTime() + snappedOffsetMs)
              goal.endDate = new Date(goal._newFutureStart.getTime() + origDuration)
              // Start date stays at original (anchored to history)
              goal.startDate = goal._origStartDate
            } else {
              // Move mode: shift both start and end
              goal.startDate = new Date(goal._origStartDate.getTime() + snappedOffsetMs)
              goal.endDate = new Date(goal._origEndDate.getTime() + snappedOffsetMs)
            }

            // Update drag tooltip
            const mode = goal._isPostponeMode ? "postpone" : "move"
            dragTooltip
              .html(self.formatDragTooltip(goal.startDate, goal.endDate, daysShifted, null, mode, goal._newFutureStart))
              .style("left", `${event.sourceEvent.offsetX + 20}px`)
              .style("top", `${event.sourceEvent.offsetY - 60}px`)

            // Visual shift - in postpone mode, only shift future elements
            const shift = goal._isPostponeMode
              ? xScale(goal._newFutureStart) - xScale(goal._lockDate)
              : xScale(goal.startDate) - xScale(goal._origStartDate)

            d3.select(this).selectAll("rect").each(function() {
              const el = d3.select(this)
              const origX = parseFloat(el.attr("data-orig-x") || el.attr("x"))
              if (!el.attr("data-orig-x")) el.attr("data-orig-x", el.attr("x"))
              el.attr("x", origX + shift)
            })
            d3.select(this).selectAll("text").each(function() {
              const el = d3.select(this)
              const origX = parseFloat(el.attr("data-orig-x") || el.attr("x"))
              if (!el.attr("data-orig-x")) el.attr("data-orig-x", el.attr("x"))
              el.attr("x", origX + shift)
            })
            d3.select(this).selectAll("path").each(function() {
              const el = d3.select(this)
              if (!el.attr("data-orig-transform")) el.attr("data-orig-transform", el.attr("transform") || "")
              el.attr("transform", `translate(${shift}, 0)`)
            })
          })
          .on("end", function() {
            const blockEl = d3.select(this)

            // Remove ghost outlines
            if (goal._ghostGroup) {
              goal._ghostGroup.remove()
              goal._ghostGroup = null
            }
            if (goal._lockedGhost) {
              goal._lockedGhost.remove()
              goal._lockedGhost = null
            }

            // Hide drag tooltip
            dragTooltip.classed("hidden", true)

            // Reset visual enhancements
            blockEl
              .style("filter", null)
              .style("transform", null)

            blockEl.selectAll(".block-fill")
              .style("opacity", 0.85)
              .style("stroke", null)
              .style("stroke-width", null)

            // Check for date changes
            const hasDateChange = goal.endDate.getTime() !== goal._origEndDate.getTime() ||
                                  goal.startDate.getTime() !== goal._origStartDate.getTime()

            if (hasDateChange) {
              // In postpone mode, send the new future start to the API
              if (goal._isPostponeMode && goal._newFutureStart) {
                self.updateGoalDates(goal.id, goal._newFutureStart, goal.endDate)
              } else {
                self.updateGoalDates(goal.id, goal.startDate, goal.endDate)
              }
            }
          })
        )
      }

      // Hover effects
      blockGroup.on("mouseenter", function(event) {
        d3.select(this).selectAll(".block-fill").style("opacity", 1)

        const dataSource = goal.uses_actual_data
          ? '<span class="text-green-400">Based on actual reading speed</span>'
          : '<span class="text-gray-400">Estimated from difficulty</span>'

        let daysLine
        if (goal.goal_status === "completed") {
          daysLine = '<span class="text-green-400">Completed</span>'
        } else if (goal.goal_status === "abandoned") {
          daysLine = '<span class="text-red-400">Abandoned</span>'
        } else if (goal.days_remaining > 0 && goal.startDate <= new Date()) {
          const suffix = !goal.include_weekends ? ` <span class="text-gray-500">(${goal.calendar_days} calendar)</span>` : ""
          daysLine = `${goal.days_remaining} days remaining${suffix}`
        } else {
          const suffix = !goal.include_weekends ? ` <span class="text-gray-500">(${goal.calendar_days} calendar)</span>` : ""
          daysLine = `${goal.duration_days} day duration${suffix}`
        }

        // Calculate total actual reading time
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

        tooltip
          .html(`
            <div class="font-semibold mb-1">${goal.title}</div>
            <div class="text-gray-300 text-xs">${goal.author || "Unknown author"}</div>
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
          `)
          .classed("hidden", false)
          .style("left", `${event.offsetX + 15}px`)
          .style("top", `${event.offsetY - 10}px`)
      })

      blockGroup.on("mousemove", function(event) {
        tooltip
          .style("left", `${event.offsetX + 15}px`)
          .style("top", `${event.offsetY - 10}px`)
      })

      blockGroup.on("mouseleave", function() {
        d3.select(this).selectAll(".block-fill").style("opacity", 0.85)
        tooltip.classed("hidden", true)
      })

      blockGroup.on("click", (event) => {
        if (event.defaultPrevented) return
        window.location.href = `/reading_goals/${goal.id}`
      })
    })

    // Legend (color blocks matching each book)
    if (!this.compactValue) {
      this.renderLegend(goals)
    }
  }

  niceMinuteTicks(totalMinutes) {
    if (totalMinutes <= 30) return d3.range(0, totalMinutes + 1, 5)
    if (totalMinutes <= 60) return d3.range(0, totalMinutes + 1, 10)
    if (totalMinutes <= 120) return d3.range(0, totalMinutes + 1, 15)
    if (totalMinutes <= 240) return d3.range(0, totalMinutes + 1, 30)
    return d3.range(0, totalMinutes + 1, 60)
  }

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
  }

  async updateGoalDates(goalId, startDate, endDate) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const formatDate = (d) => d.toISOString().split("T")[0]

    try {
      const response = await fetch(`/api/v1/pipeline/${goalId}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "X-Requested-With": "XMLHttpRequest"
        },
        credentials: "same-origin",
        body: JSON.stringify({
          start_date: formatDate(startDate),
          end_date: formatDate(endDate)
        })
      })

      if (!response.ok) {
        console.error("Failed to update goal dates")
      }
      // Always reload to get recalculated layout
      this.loadData()
    } catch (error) {
      console.error("Error updating goal:", error)
      this.loadData()
    }
  }

  formatDragTooltip(startDate, endDate, daysShifted, sessionInfo = null, mode = "move", newFutureStart = null) {
    const formatDate = d3.timeFormat("%b %d")
    const startStr = formatDate(startDate)
    const endStr = formatDate(endDate)

    if (mode === "postpone") {
      // Postpone mode - show different UI
      let shiftText = ""
      if (daysShifted > 0) {
        shiftText = `<div class="text-amber-400 font-medium">⏸ Postponing ${daysShifted} day${daysShifted !== 1 ? "s" : ""}</div>`
      } else if (daysShifted < 0) {
        shiftText = `<div class="text-cyan-400 font-medium">⏩ Moving up ${Math.abs(daysShifted)} day${Math.abs(daysShifted) !== 1 ? "s" : ""}</div>`
      } else {
        shiftText = `<div class="text-gray-400">No change</div>`
      }

      const futureStartStr = newFutureStart ? formatDate(newFutureStart) : formatDate(startDate)

      return `
        <div class="text-xs space-y-1">
          <div class="font-semibold text-white">Postponing remaining work:</div>
          <div class="mt-1 pt-1 border-t border-green-500/30">
            <div class="text-green-400 text-[10px]">📌 History preserved</div>
          </div>
          <div><span class="text-gray-400">Resume on:</span> ${futureStartStr}</div>
          <div><span class="text-gray-400">Finish by:</span> ${endStr}</div>
          ${shiftText}
        </div>
      `
    }

    // Move mode - original behavior
    let shiftText = ""
    if (daysShifted > 0) {
      shiftText = `<div class="text-amber-400 font-medium">→ ${daysShifted} day${daysShifted !== 1 ? "s" : ""} later</div>`
    } else if (daysShifted < 0) {
      shiftText = `<div class="text-cyan-400 font-medium">← ${Math.abs(daysShifted)} day${Math.abs(daysShifted) !== 1 ? "s" : ""} earlier</div>`
    } else {
      shiftText = `<div class="text-gray-400">No change</div>`
    }

    return `
      <div class="text-xs space-y-1">
        <div class="font-semibold text-white">Moving to:</div>
        <div><span class="text-gray-400">Start:</span> ${startStr}</div>
        <div><span class="text-gray-400">End:</span> ${endStr}</div>
        ${shiftText}
      </div>
    `
  }

  formatResizeTooltip(endDate, daysChanged) {
    const formatDate = d3.timeFormat("%b %d")
    const endStr = formatDate(endDate)

    let changeText = ""
    if (daysChanged > 0) {
      changeText = `<div class="text-amber-400 font-medium">+${daysChanged} day${daysChanged !== 1 ? "s" : ""}</div>`
    } else if (daysChanged < 0) {
      changeText = `<div class="text-cyan-400 font-medium">${daysChanged} day${Math.abs(daysChanged) !== 1 ? "s" : ""}</div>`
    } else {
      changeText = `<div class="text-gray-400">No change</div>`
    }

    return `
      <div class="text-xs space-y-1">
        <div class="font-semibold text-white">New end date:</div>
        <div>${endStr}</div>
        ${changeText}
      </div>
    `
  }

  debounce(func, wait) {
    let timeout
    return (...args) => {
      clearTimeout(timeout)
      timeout = setTimeout(() => func.apply(this, args), wait)
    }
  }
}
