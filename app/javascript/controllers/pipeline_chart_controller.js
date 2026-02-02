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

  // Assign each goal a fixed vertical lane and produce segments.
  // Goals are stacked bottom-up based on time overlap (longest on bottom).
  // Each goal stays at a consistent y-position for its entire span,
  // with gaps only for weekend exclusions.
  computeSegments(goals) {
    // Assign fixed y-offsets by stacking overlapping goals.
    // Goals are already sorted by duration descending (longest first = bottom).
    const goalLanes = new Map()

    goals.forEach(goal => {
      let yOffset = 0
      goals.forEach(other => {
        if (other.id === goal.id || !goalLanes.has(other.id)) return
        // Check time overlap
        if (goal.startDate < other.endDate && goal.endDate > other.startDate) {
          yOffset = Math.max(yOffset, goalLanes.get(other.id) + other.minutes_per_day)
        }
      })
      goalLanes.set(goal.id, yOffset)
    })

    // Build segments for each goal. Goals that include weekends get a single
    // segment spanning their full range. Goals excluding weekends get one
    // segment per contiguous weekday run.
    const segmentsByGoal = new Map()

    goals.forEach(goal => {
      const yOffset = goalLanes.get(goal.id)

      if (goal.include_weekends) {
        segmentsByGoal.set(goal.id, [{
          startDate: goal.startDate,
          endDate: goal.endDate,
          yOffset,
          minutes_per_day: goal.minutes_per_day
        }])
      } else {
        const segments = []
        let cursor = new Date(goal.startDate)
        let segStart = null

        while (cursor < goal.endDate) {
          const dow = cursor.getDay()
          const isWeekend = dow === 0 || dow === 6

          if (!isWeekend) {
            if (!segStart) segStart = new Date(cursor)
          } else if (segStart) {
            segments.push({
              startDate: segStart,
              endDate: new Date(cursor),
              yOffset,
              minutes_per_day: goal.minutes_per_day
            })
            segStart = null
          }
          cursor = new Date(cursor.getTime() + 86400000)
        }

        if (segStart) {
          segments.push({
            startDate: segStart,
            endDate: goal.endDate,
            yOffset,
            minutes_per_day: goal.minutes_per_day
          })
        }

        segmentsByGoal.set(goal.id, segments)
      }
    })

    // Compute max Y
    let maxY = 0
    goalLanes.forEach((yOffset, goalId) => {
      const goal = goals.find(g => g.id === goalId)
      maxY = Math.max(maxY, yOffset + goal.minutes_per_day)
    })

    return { segmentsByGoal, maxY }
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
    let goals = this.chartData.goals
      .filter(g => g.start_date && g.end_date && g.minutes_per_day > 0)
      .map(g => ({
        ...g,
        startDate: new Date(g.start_date + "T00:00:00"),
        endDate: new Date(g.end_date + "T00:00:00")
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

    // Compute fixed-lane segments
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

    // Draw each goal as a fixed-lane block
    const self = this
    goals.forEach(goal => {
      const segments = segmentsByGoal.get(goal.id)
      if (!segments || segments.length === 0) return

      const yOffset = segments[0].yOffset
      const blockGroup = svg.append("g")
        .attr("class", "pipeline-block cursor-pointer")
        .datum(goal)

      // Block dimensions (consistent across all segments)
      const blockY = yScale(yOffset + goal.minutes_per_day)
      const blockHeight = Math.max(yScale(yOffset) - blockY, 1)

      // Draw each segment as a rect
      segments.forEach(seg => {
        const x = xScale(seg.startDate)
        const segWidth = Math.max(xScale(seg.endDate) - x, 1)

        blockGroup.append("rect")
          .attr("class", "block-fill")
          .attr("x", x)
          .attr("y", blockY)
          .attr("width", segWidth)
          .attr("height", blockHeight)
          .attr("rx", 3)
          .style("fill", goal.color)
          .style("opacity", 0.85)
      })

      // Progress overlay — spans from startDate across progress %
      const progressEndDate = new Date(goal.startDate.getTime() + (goal.endDate.getTime() - goal.startDate.getTime()) * (goal.progress / 100))

      segments.forEach(seg => {
        if (seg.endDate <= goal.startDate || seg.startDate >= progressEndDate) return

        const clipStart = Math.max(seg.startDate.getTime(), goal.startDate.getTime())
        const clipEnd = Math.min(seg.endDate.getTime(), progressEndDate.getTime())
        const x = xScale(new Date(clipStart))
        const w = Math.max(xScale(new Date(clipEnd)) - x, 0)

        if (w > 0) {
          blockGroup.append("rect")
            .attr("class", "block-progress")
            .attr("x", x)
            .attr("y", blockY)
            .attr("width", w)
            .attr("height", blockHeight)
            .attr("rx", 3)
            .style("fill", d3.color(goal.color).darker(0.5))
            .style("opacity", 0.4)
        }
      })

      // Estimate indicator (dashed inner border on widest segment)
      if (!goal.uses_actual_data) {
        const widest = segments.reduce((a, b) =>
          (xScale(b.endDate) - xScale(b.startDate)) > (xScale(a.endDate) - xScale(a.startDate)) ? b : a
        )
        const wx = xScale(widest.startDate) + 1
        const ww = Math.max(xScale(widest.endDate) - xScale(widest.startDate) - 2, 4)

        blockGroup.append("rect")
          .attr("x", wx).attr("y", blockY + 1)
          .attr("width", ww).attr("height", Math.max(blockHeight - 2, 1))
          .attr("rx", 2)
          .style("fill", "none")
          .style("stroke", "rgba(255,255,255,0.3)")
          .style("stroke-width", 1)
          .style("stroke-dasharray", "3,3")
      }

      // Create a clipPath from all segments so text doesn't overflow into gaps
      const clipId = `clip-goal-${goal.id}`
      const clipPath = svg.append("defs").append("clipPath").attr("id", clipId)
      segments.forEach(seg => {
        const cx = xScale(seg.startDate)
        const cw = Math.max(xScale(seg.endDate) - cx, 1)
        clipPath.append("rect").attr("x", cx).attr("y", blockY).attr("width", cw).attr("height", blockHeight)
      })

      // Book title label — spans the full goal width, clipped to segments
      const fullLabelWidth = xScale(goal.endDate) - xScale(goal.startDate)

      if (fullLabelWidth >= 60 && blockHeight >= 18) {
        const maxChars = Math.floor((fullLabelWidth - 16) / 7)
        const title = goal.title.length > maxChars ? goal.title.substring(0, maxChars - 1) + "\u2026" : goal.title

        blockGroup.append("text")
          .attr("clip-path", `url(#${clipId})`)
          .attr("x", xScale(goal.startDate) + 8)
          .attr("y", blockY + blockHeight / 2)
          .attr("dy", "0.35em")
          .style("fill", "#fff")
          .style("font-size", blockHeight >= 28 ? "12px" : "10px")
          .style("font-weight", "600")
          .style("text-shadow", "0 1px 2px rgba(0,0,0,0.3)")
          .style("pointer-events", "none")
          .text(title)
      }

      // Minutes/day label on right edge
      if (!this.compactValue && blockHeight >= 18 && fullLabelWidth >= 80) {
        blockGroup.append("text")
          .attr("clip-path", `url(#${clipId})`)
          .attr("x", xScale(goal.endDate) - 8)
          .attr("y", blockY + blockHeight / 2)
          .attr("dy", "0.35em")
          .attr("text-anchor", "end")
          .style("fill", "rgba(255,255,255,0.8)")
          .style("font-size", "10px")
          .style("font-weight", "500")
          .style("text-shadow", "0 1px 2px rgba(0,0,0,0.3)")
          .style("pointer-events", "none")
          .text(`${goal.minutes_per_day}m/day`)
      }

      // Resize handle (right edge of the last segment)
      const lastSeg = segments[segments.length - 1]
      blockGroup.append("rect")
        .attr("class", "resize-handle")
        .attr("x", xScale(lastSeg.endDate) - 5)
        .attr("y", blockY)
        .attr("width", 5)
        .attr("height", Math.max(blockHeight, 2))
        .style("fill", "transparent")
        .style("cursor", "ew-resize")
        .call(d3.drag()
          .on("start", function(event) {
            goal._resizeStartX = event.x
            goal._origEndDate = goal.endDate
            d3.select(this).style("fill", "rgba(255,255,255,0.3)")
          })
          .on("drag", function(event) {
            const dx = event.x - goal._resizeStartX
            const newEnd = new Date(goal._origEndDate.getTime() + dx / width * (endDate - startDate))
            if (newEnd > goal.startDate) {
              goal.endDate = newEnd
              d3.select(this).attr("x", xScale(goal.endDate) - 5)
            }
          })
          .on("end", function() {
            d3.select(this).style("fill", "transparent")
            if (goal.endDate !== goal._origEndDate) {
              self.updateGoalDates(goal.id, goal.startDate, goal.endDate)
            }
          })
        )

      // Drag to move entire block horizontally
      blockGroup.call(d3.drag()
        .filter(function(event) {
          return !event.target.classList.contains("resize-handle")
        })
        .on("start", function(event) {
          goal._dragStartX = event.x
          goal._origStartDate = goal.startDate
          goal._origEndDate = goal.endDate
          d3.select(this).raise().style("opacity", 0.7)
        })
        .on("drag", function(event) {
          const dx = event.x - goal._dragStartX
          const msPerPx = (endDate - startDate) / width
          const offsetMs = dx * msPerPx
          goal.startDate = new Date(goal._origStartDate.getTime() + offsetMs)
          goal.endDate = new Date(goal._origEndDate.getTime() + offsetMs)

          // Shift all rects in this group horizontally
          const shift = xScale(goal.startDate) - xScale(goal._origStartDate)
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
        })
        .on("end", function() {
          d3.select(this).style("opacity", 1)
          if (goal.startDate.getTime() !== goal._origStartDate.getTime()) {
            self.updateGoalDates(goal.id, goal.startDate, goal.endDate)
          }
        })
      )

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

        tooltip
          .html(`
            <div class="font-semibold mb-1">${goal.title}</div>
            <div class="text-gray-300 text-xs">${goal.author || "Unknown author"}</div>
            <div class="mt-2 space-y-1 text-xs">
              <div><span class="text-gray-400">Minutes/day:</span> ${goal.minutes_per_day}</div>
              <div>${daysLine}</div>
              <div><span class="text-gray-400">Pages:</span> ${goal.total_pages}</div>
              <div><span class="text-gray-400">Progress:</span> ${goal.progress}%</div>
              <div><span class="text-gray-400">Pages/day:</span> ${goal.pages_per_day}</div>
              <div><span class="text-gray-400">Est. remaining:</span> ${(goal.estimated_hours || 0).toFixed(1)}h</div>
              <div>${dataSource}</div>
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

  debounce(func, wait) {
    let timeout
    return (...args) => {
      clearTimeout(timeout)
      timeout = setTimeout(() => func.apply(this, args), wait)
    }
  }
}
