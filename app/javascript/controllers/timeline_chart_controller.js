import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"

// Connects to data-controller="timeline-chart"
export default class extends Controller {
  static values = {
    url: String,
    compact: { type: Boolean, default: false }
  }

  connect() {
    this.margin = { top: 30, right: 30, bottom: 50, left: 150 }
    this.rowHeight = this.compactValue ? 32 : 50
    this.minWidth = 600

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
      console.error("Timeline chart fetch error:", error)
      this.element.innerHTML = `
        <div class="flex items-center justify-center h-48 text-gray-500">
          <p>Unable to load timeline: ${error.message}</p>
        </div>
      `
      return
    }

    try {
      this.render()
    } catch (error) {
      console.error("Timeline chart render error:", error)
      this.element.innerHTML = `
        <div class="flex items-center justify-center h-48 text-red-500">
          <p>Error rendering timeline: ${error.message}</p>
        </div>
      `
    }
  }

  render() {
    if (!this.chartData || !this.chartData.goals.length) {
      this.element.innerHTML = `
        <div class="flex items-center justify-center h-48 text-gray-500">
          <p>Create a reading goal to see your timeline.</p>
        </div>
      `
      return
    }

    this.element.innerHTML = ""

    const containerWidth = this.element.clientWidth
    const width = Math.max(containerWidth, this.minWidth) - this.margin.left - this.margin.right

    // Parse dates and filter goals with valid dates
    // Append T00:00:00 to avoid UTC midnight parsing issues
    const goals = this.chartData.goals.filter(g => g.start_date && g.end_date).map(g => ({
      ...g,
      startDate: new Date(g.start_date + "T00:00:00"),
      endDate: new Date(g.end_date + "T00:00:00")
    }))

    if (goals.length === 0) {
      this.element.innerHTML = `
        <div class="flex items-center justify-center h-48 text-gray-500">
          <p>Set dates on your reading goals to see them on the timeline.</p>
        </div>
      `
      return
    }

    const height = goals.length * this.rowHeight

    // Create SVG
    const svg = d3.select(this.element)
      .append("svg")
      .attr("width", width + this.margin.left + this.margin.right)
      .attr("height", height + this.margin.top + this.margin.bottom)
      .append("g")
      .attr("transform", `translate(${this.margin.left},${this.margin.top})`)

    // Date range with padding
    const minDate = d3.min(goals, d => d.startDate)
    const maxDate = d3.max(goals, d => d.endDate)
    const daysPadding = 7
    const startDate = d3.timeDay.offset(minDate, -daysPadding)
    const endDate = d3.timeDay.offset(maxDate, daysPadding)

    // X scale (time)
    const xScale = d3.scaleTime()
      .domain([startDate, endDate])
      .range([0, width])

    // Y scale (one row per goal)
    const yScale = d3.scaleBand()
      .domain(goals.map((_, i) => i))
      .range([0, height])
      .padding(0.2)

    // X axis
    const xAxis = d3.axisBottom(xScale)
      .ticks(d3.timeWeek.every(1))
      .tickFormat(d3.timeFormat("%b %d"))

    svg.append("g")
      .attr("class", "x-axis")
      .attr("transform", `translate(0,${height})`)
      .call(xAxis)
      .selectAll("text")
      .style("font-size", "11px")
      .style("fill", "#6b7280")

    // Y axis (book titles)
    const yAxis = d3.axisLeft(yScale)
      .tickFormat(i => this.truncateTitle(goals[i].title, 18))

    svg.append("g")
      .attr("class", "y-axis")
      .call(yAxis)
      .selectAll("text")
      .style("font-size", "12px")
      .style("fill", "#374151")

    // Grid lines
    svg.append("g")
      .attr("class", "grid")
      .attr("transform", `translate(0,${height})`)
      .call(
        d3.axisBottom(xScale)
          .ticks(d3.timeWeek.every(1))
          .tickSize(-height)
          .tickFormat("")
      )
      .selectAll("line")
      .style("stroke", "#e5e7eb")
      .style("stroke-dasharray", "2,2")

    // Today marker
    const today = new Date()
    if (today >= startDate && today <= endDate) {
      svg.append("line")
        .attr("x1", xScale(today))
        .attr("x2", xScale(today))
        .attr("y1", 0)
        .attr("y2", height)
        .style("stroke", "#ef4444")
        .style("stroke-width", 2)
        .style("stroke-dasharray", "4,4")

      svg.append("text")
        .attr("x", xScale(today))
        .attr("y", -10)
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

    // Draw goal bars
    const self = this
    const bars = svg.selectAll(".goal-bar")
      .data(goals)
      .enter()
      .append("g")
      .attr("class", "goal-bar cursor-pointer")
      .attr("transform", (d, i) => `translate(${xScale(d.startDate)},${yScale(i)})`)

    // Background bar
    bars.append("rect")
      .attr("class", "bar-bg")
      .attr("width", d => Math.max(xScale(d.endDate) - xScale(d.startDate), 20))
      .attr("height", yScale.bandwidth())
      .attr("rx", 6)
      .attr("ry", 6)
      .style("fill", d => this.getBarColor(d))
      .style("opacity", 0.2)

    // Progress bar
    bars.append("rect")
      .attr("class", "bar-progress")
      .attr("width", d => {
        const fullWidth = Math.max(xScale(d.endDate) - xScale(d.startDate), 20)
        return fullWidth * (d.progress / 100)
      })
      .attr("height", yScale.bandwidth())
      .attr("rx", 6)
      .attr("ry", 6)
      .style("fill", d => this.getBarColor(d))
      .style("opacity", 0.8)

    // Book title text on bar
    if (!this.compactValue) {
      bars.append("text")
        .attr("x", 8)
        .attr("y", yScale.bandwidth() / 2)
        .attr("dy", "0.35em")
        .style("fill", "#111827")
        .style("font-size", "12px")
        .style("font-weight", "500")
        .text(d => this.truncateTitle(d.title, Math.floor((xScale(d.endDate) - xScale(d.startDate) - 16) / 7)))
    }

    // Resize handle (right edge)
    bars.append("rect")
      .attr("class", "resize-handle")
      .attr("x", d => Math.max(xScale(d.endDate) - xScale(d.startDate), 20) - 6)
      .attr("width", 6)
      .attr("height", yScale.bandwidth())
      .attr("rx", 2)
      .style("fill", "transparent")
      .style("cursor", "ew-resize")
      .call(d3.drag()
        .on("start", function(event, d) {
          d._resizeStartX = event.x
          d._origEndDate = d.endDate
          d3.select(this).style("fill", "rgba(0,0,0,0.2)")
        })
        .on("drag", function(event, d) {
          const dx = event.x - d._resizeStartX
          const newEnd = new Date(d._origEndDate.getTime() + dx / width * (endDate - startDate))
          if (newEnd > d.startDate) {
            d.endDate = newEnd
            const bar = d3.select(this.parentNode)
            const barWidth = Math.max(xScale(d.endDate) - xScale(d.startDate), 20)
            bar.select(".bar-bg").attr("width", barWidth)
            bar.select(".bar-progress").attr("width", barWidth * (d.progress / 100))
            d3.select(this).attr("x", barWidth - 6)
          }
        })
        .on("end", function(event, d) {
          d3.select(this).style("fill", "transparent")
          if (d.endDate !== d._origEndDate) {
            self.updateGoalDates(d.id, d.startDate, d.endDate)
          }
        })
      )

    // Drag to move entire bar
    bars.call(d3.drag()
      .filter(function(event) {
        // Don't drag when clicking the resize handle
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
        d3.select(this).attr("transform", `translate(${xScale(d.startDate)},${yScale(goals.indexOf(d))})`)
      })
      .on("end", function(event, d) {
        d3.select(this).style("opacity", 1)
        if (d.startDate.getTime() !== d._origStartDate.getTime()) {
          self.updateGoalDates(d.id, d.startDate, d.endDate)
        }
      })
    )

    // Hover effects
    bars.on("mouseenter", function(event, d) {
      const bar = d3.select(this)
      bar.select(".bar-progress").style("opacity", 1)
      bar.select(".bar-bg").style("opacity", 0.3)

      const durationDays = Math.ceil((d.endDate - d.startDate) / (1000 * 60 * 60 * 24))
      const trackStatus = d.on_track ? '<span class="text-green-400">On Track</span>' : '<span class="text-amber-400">Behind</span>'

      tooltip
        .html(`
          <div class="font-semibold mb-1">${d.title}</div>
          <div class="text-gray-300 text-xs">${d.author || "Unknown author"}</div>
          <div class="mt-2 space-y-1 text-xs">
            <div><span class="text-gray-400">Pages:</span> ${d.total_pages}</div>
            <div><span class="text-gray-400">Progress:</span> ${d.progress}%</div>
            <div><span class="text-gray-400">Duration:</span> ${durationDays} days</div>
            <div><span class="text-gray-400">Pages/day:</span> ${d.pages_per_day}</div>
            <div><span class="text-gray-400">Est. time:</span> ${(d.estimated_hours || 0).toFixed(1)}h</div>
            <div><span class="text-gray-400">Status:</span> ${d.goal_status} ${d.goal_status === "active" ? `(${trackStatus})` : ""}</div>
          </div>
        `)
        .classed("hidden", false)
        .style("left", `${event.offsetX + 10}px`)
        .style("top", `${event.offsetY + 10}px`)
    })

    bars.on("mouseleave", function() {
      const bar = d3.select(this)
      bar.select(".bar-progress").style("opacity", 0.8)
      bar.select(".bar-bg").style("opacity", 0.2)
      tooltip.classed("hidden", true)
    })

    bars.on("click", (event, d) => {
      if (event.defaultPrevented) return // ignore drag clicks
      window.location.href = `/reading_goals/${d.id}`
    })

    // Legend
    if (!this.compactValue) {
      this.renderLegend()
    }
  }

  getBarColor(d) {
    if (d.goal_status === "completed") return "#10b981"   // green
    if (d.goal_status === "abandoned") return "#ef4444"    // red
    if (d.goal_status === "active" && !d.on_track) return "#f59e0b"  // amber
    if (d.goal_status === "active") return "#3b82f6"       // blue
    return "#9ca3af"  // gray for future/unstarted
  }

  renderLegend() {
    const legendData = [
      { label: "Active", color: "#3b82f6" },
      { label: "Behind", color: "#f59e0b" },
      { label: "Completed", color: "#10b981" },
      { label: "Future", color: "#9ca3af" }
    ]

    const legend = d3.select(this.element)
      .append("div")
      .attr("class", "flex flex-wrap gap-4 mt-4 justify-center text-sm")

    legend.selectAll(".legend-item")
      .data(legendData)
      .enter()
      .append("div")
      .attr("class", "legend-item flex items-center gap-2")
      .html(d => `
        <span class="w-3 h-3 rounded" style="background-color: ${d.color}"></span>
        <span class="text-gray-600">${d.label}</span>
      `)
  }

  async updateGoalDates(goalId, startDate, endDate) {
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    const formatDate = (d) => d.toISOString().split("T")[0]

    try {
      const response = await fetch(`/api/v1/timeline/${goalId}`, {
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
        this.loadData() // reload to revert
      }
    } catch (error) {
      console.error("Error updating goal:", error)
      this.loadData()
    }
  }

  truncateTitle(title, maxChars) {
    if (!maxChars || maxChars < 4) return ""
    if (title.length <= maxChars) return title
    return title.substring(0, maxChars - 3) + "..."
  }

  debounce(func, wait) {
    let timeout
    return (...args) => {
      clearTimeout(timeout)
      timeout = setTimeout(() => func.apply(this, args), wait)
    }
  }
}
