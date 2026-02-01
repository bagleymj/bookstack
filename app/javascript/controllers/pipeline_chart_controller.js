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

    // Assign colors and compute stack offsets based on time overlap
    // Each block sits on top of overlapping blocks below it (like Breakout)
    const placed = []
    goals.forEach((g, i) => {
      g.color = this.constructor.BLOCK_COLORS[i % this.constructor.BLOCK_COLORS.length]

      // Find all already-placed goals that overlap in time with this one
      const overlapping = placed.filter(p =>
        p.startDate < g.endDate && p.endDate > g.startDate
      )

      // Stack on top of the highest overlapping block
      g.yOffset = overlapping.length > 0
        ? Math.max(...overlapping.map(p => p.yOffset + p.minutes_per_day))
        : 0

      placed.push(g)
    })

    // Total Y extent is the max top edge of any block
    const totalMinutes = Math.max(...goals.map(g => g.yOffset + g.minutes_per_day))

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

    // Draw Breakout blocks
    const self = this
    const blocks = svg.selectAll(".pipeline-block")
      .data(goals)
      .enter()
      .append("g")
      .attr("class", "pipeline-block cursor-pointer")

    // Main colored block
    blocks.append("rect")
      .attr("class", "block-fill")
      .attr("x", d => xScale(d.startDate))
      .attr("y", d => yScale(d.yOffset + d.minutes_per_day))
      .attr("width", d => Math.max(xScale(d.endDate) - xScale(d.startDate), 8))
      .attr("height", d => Math.max(yScale(d.yOffset) - yScale(d.yOffset + d.minutes_per_day), 2))
      .attr("rx", 3)
      .attr("ry", 3)
      .style("fill", d => d.color)
      .style("opacity", 0.85)
      .style("stroke", d => d3.color(d.color).darker(0.3))
      .style("stroke-width", 1)

    // Progress overlay (darker shade showing how much is read)
    blocks.append("rect")
      .attr("class", "block-progress")
      .attr("x", d => xScale(d.startDate))
      .attr("y", d => yScale(d.yOffset + d.minutes_per_day))
      .attr("width", d => {
        const fullWidth = Math.max(xScale(d.endDate) - xScale(d.startDate), 8)
        return fullWidth * (d.progress / 100)
      })
      .attr("height", d => Math.max(yScale(d.yOffset) - yScale(d.yOffset + d.minutes_per_day), 2))
      .attr("rx", 3)
      .attr("ry", 3)
      .style("fill", d => d3.color(d.color).darker(0.5))
      .style("opacity", 0.4)

    // Estimate indicator (dashed border for estimated vs actual data)
    blocks.filter(d => !d.uses_actual_data)
      .append("rect")
      .attr("class", "block-estimate-indicator")
      .attr("x", d => xScale(d.startDate) + 1)
      .attr("y", d => yScale(d.yOffset + d.minutes_per_day) + 1)
      .attr("width", d => Math.max(xScale(d.endDate) - xScale(d.startDate) - 2, 6))
      .attr("height", d => Math.max(yScale(d.yOffset) - yScale(d.yOffset + d.minutes_per_day) - 2, 1))
      .attr("rx", 2)
      .style("fill", "none")
      .style("stroke", "rgba(255,255,255,0.3)")
      .style("stroke-width", 1)
      .style("stroke-dasharray", "3,3")

    // Book title labels (inside blocks when large enough)
    blocks.each(function(d) {
      const blockWidth = Math.max(xScale(d.endDate) - xScale(d.startDate), 8)
      const blockHeight = Math.max(yScale(d.yOffset) - yScale(d.yOffset + d.minutes_per_day), 2)
      const minWidthForText = 60
      const minHeightForText = 18

      if (blockWidth >= minWidthForText && blockHeight >= minHeightForText) {
        const maxChars = Math.floor((blockWidth - 16) / 7)
        const title = d.title.length > maxChars ? d.title.substring(0, maxChars - 1) + "\u2026" : d.title

        d3.select(this).append("text")
          .attr("x", xScale(d.startDate) + 8)
          .attr("y", yScale(d.yOffset + d.minutes_per_day) + blockHeight / 2)
          .attr("dy", "0.35em")
          .style("fill", "#fff")
          .style("font-size", blockHeight >= 28 ? "12px" : "10px")
          .style("font-weight", "600")
          .style("text-shadow", "0 1px 2px rgba(0,0,0,0.3)")
          .style("pointer-events", "none")
          .text(title)
      }
    })

    // Minutes/day label on right side of block (when tall enough)
    if (!this.compactValue) {
      blocks.each(function(d) {
        const blockWidth = Math.max(xScale(d.endDate) - xScale(d.startDate), 8)
        const blockHeight = Math.max(yScale(d.yOffset) - yScale(d.yOffset + d.minutes_per_day), 2)

        if (blockHeight >= 18 && blockWidth >= 80) {
          d3.select(this).append("text")
            .attr("x", xScale(d.endDate) - 8)
            .attr("y", yScale(d.yOffset + d.minutes_per_day) + blockHeight / 2)
            .attr("dy", "0.35em")
            .attr("text-anchor", "end")
            .style("fill", "rgba(255,255,255,0.8)")
            .style("font-size", "10px")
            .style("font-weight", "500")
            .style("text-shadow", "0 1px 2px rgba(0,0,0,0.3)")
            .style("pointer-events", "none")
            .text(`${d.minutes_per_day}m/day`)
        }
      })
    }

    // Resize handle (right edge of each block)
    blocks.append("rect")
      .attr("class", "resize-handle")
      .attr("x", d => xScale(d.endDate) - 5)
      .attr("y", d => yScale(d.yOffset + d.minutes_per_day))
      .attr("width", 5)
      .attr("height", d => Math.max(yScale(d.yOffset) - yScale(d.yOffset + d.minutes_per_day), 2))
      .style("fill", "transparent")
      .style("cursor", "ew-resize")
      .call(d3.drag()
        .on("start", function(event, d) {
          d._resizeStartX = event.x
          d._origEndDate = d.endDate
          d3.select(this).style("fill", "rgba(255,255,255,0.3)")
        })
        .on("drag", function(event, d) {
          const dx = event.x - d._resizeStartX
          const newEnd = new Date(d._origEndDate.getTime() + dx / width * (endDate - startDate))
          if (newEnd > d.startDate) {
            d.endDate = newEnd
            const block = d3.select(this.parentNode)
            const blockWidth = Math.max(xScale(d.endDate) - xScale(d.startDate), 8)
            block.select(".block-fill").attr("width", blockWidth)
            block.select(".block-progress").attr("width", blockWidth * (d.progress / 100))
            d3.select(this).attr("x", xScale(d.endDate) - 5)
          }
        })
        .on("end", function(event, d) {
          d3.select(this).style("fill", "transparent")
          if (d.endDate !== d._origEndDate) {
            self.updateGoalDates(d.id, d.startDate, d.endDate)
          }
        })
      )

    // Drag to move entire block horizontally
    blocks.call(d3.drag()
      .filter(function(event) {
        return !event.target.classList.contains("resize-handle")
      })
      .on("start", function(event, d) {
        d._dragStartX = event.x
        d._origStartDate = d.startDate
        d._origEndDate = d.endDate
        d3.select(this).raise().style("opacity", 0.7)
      })
      .on("drag", function(event, d) {
        const dx = event.x - d._dragStartX
        const msPerPx = (endDate - startDate) / width
        const offsetMs = dx * msPerPx
        d.startDate = new Date(d._origStartDate.getTime() + offsetMs)
        d.endDate = new Date(d._origEndDate.getTime() + offsetMs)
        const newX = xScale(d.startDate)
        const blockWidth = Math.max(xScale(d.endDate) - xScale(d.startDate), 8)
        const block = d3.select(this)
        block.select(".block-fill").attr("x", newX)
        block.select(".block-progress").attr("x", newX)
        block.select(".resize-handle").attr("x", newX + blockWidth - 5)
        block.selectAll("text").each(function() {
          const el = d3.select(this)
          if (el.attr("text-anchor") === "end") {
            el.attr("x", newX + blockWidth - 8)
          } else {
            el.attr("x", newX + 8)
          }
        })
      })
      .on("end", function(event, d) {
        d3.select(this).style("opacity", 1)
        if (d.startDate.getTime() !== d._origStartDate.getTime()) {
          self.updateGoalDates(d.id, d.startDate, d.endDate)
        }
      })
    )

    // Hover effects
    blocks.on("mouseenter", function(event, d) {
      d3.select(this).select(".block-fill").style("opacity", 1)

      const dataSource = d.uses_actual_data
        ? '<span class="text-green-400">Based on actual reading speed</span>'
        : '<span class="text-gray-400">Estimated from difficulty</span>'

      let daysLine
      if (d.goal_status === "completed") {
        daysLine = '<span class="text-green-400">Completed</span>'
      } else if (d.goal_status === "abandoned") {
        daysLine = '<span class="text-red-400">Abandoned</span>'
      } else if (d.days_remaining > 0 && new Date(d.start_date + "T00:00:00") <= new Date()) {
        // Active: started and has days left
        const suffix = !d.include_weekends ? ` <span class="text-gray-500">(${d.calendar_days} calendar)</span>` : ""
        daysLine = `${d.days_remaining} days remaining${suffix}`
      } else {
        // Future: hasn't started yet
        const suffix = !d.include_weekends ? ` <span class="text-gray-500">(${d.calendar_days} calendar)</span>` : ""
        daysLine = `${d.duration_days} day duration${suffix}`
      }

      tooltip
        .html(`
          <div class="font-semibold mb-1">${d.title}</div>
          <div class="text-gray-300 text-xs">${d.author || "Unknown author"}</div>
          <div class="mt-2 space-y-1 text-xs">
            <div><span class="text-gray-400">Minutes/day:</span> ${d.minutes_per_day}</div>
            <div>${daysLine}</div>
            <div><span class="text-gray-400">Pages:</span> ${d.total_pages}</div>
            <div><span class="text-gray-400">Progress:</span> ${d.progress}%</div>
            <div><span class="text-gray-400">Pages/day:</span> ${d.pages_per_day}</div>
            <div><span class="text-gray-400">Est. remaining:</span> ${(d.estimated_hours || 0).toFixed(1)}h</div>
            <div>${dataSource}</div>
          </div>
        `)
        .classed("hidden", false)
        .style("left", `${event.offsetX + 15}px`)
        .style("top", `${event.offsetY - 10}px`)
    })

    blocks.on("mousemove", function(event) {
      tooltip
        .style("left", `${event.offsetX + 15}px`)
        .style("top", `${event.offsetY - 10}px`)
    })

    blocks.on("mouseleave", function() {
      d3.select(this).select(".block-fill").style("opacity", 0.85)
      tooltip.classed("hidden", true)
    })

    blocks.on("click", (event, d) => {
      if (event.defaultPrevented) return
      window.location.href = `/reading_goals/${d.id}`
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
      // Always reload to get recalculated minutes_per_day
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
