import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"

// Connects to data-controller="pipeline-chart"
export default class extends Controller {
  static values = {
    url: String
  }

  static targets = ["tooltip"]

  connect() {
    this.margin = { top: 30, right: 30, bottom: 50, left: 120 }
    this.rowHeight = 50
    this.minWidth = 800

    this.loadData()

    // Redraw on window resize
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

      if (!response.ok) throw new Error("Failed to load timeline data")

      this.data = await response.json()
      this.render()
    } catch (error) {
      console.error("Pipeline chart error:", error)
      this.element.innerHTML = `
        <div class="flex items-center justify-center h-48 text-gray-500">
          <p>Unable to load timeline. Please try again.</p>
        </div>
      `
    }
  }

  render() {
    if (!this.data || !this.data.books.length) {
      this.element.innerHTML = `
        <div class="flex items-center justify-center h-48 text-gray-500">
          <p>Add books to this pipeline to see the timeline visualization.</p>
        </div>
      `
      return
    }

    // Clear previous chart
    this.element.innerHTML = ""

    const containerWidth = this.element.clientWidth
    const width = Math.max(containerWidth, this.minWidth) - this.margin.left - this.margin.right

    // Calculate tracks and height
    const tracks = [...new Set(this.data.books.map(b => b.track))].sort((a, b) => a - b)
    const height = tracks.length * this.rowHeight

    // Create SVG
    const svg = d3.select(this.element)
      .append("svg")
      .attr("width", width + this.margin.left + this.margin.right)
      .attr("height", height + this.margin.top + this.margin.bottom)
      .append("g")
      .attr("transform", `translate(${this.margin.left},${this.margin.top})`)

    // Parse dates and filter books with valid dates
    const booksWithDates = this.data.books.filter(b => b.start_date && b.end_date).map(b => ({
      ...b,
      startDate: new Date(b.start_date),
      endDate: new Date(b.end_date)
    }))

    if (booksWithDates.length === 0) {
      this.element.innerHTML = `
        <div class="flex items-center justify-center h-48 text-gray-500">
          <p>Schedule books using "Auto-Schedule" or set dates manually to see the timeline.</p>
        </div>
      `
      return
    }

    // Calculate date range with padding
    const minDate = d3.min(booksWithDates, d => d.startDate)
    const maxDate = d3.max(booksWithDates, d => d.endDate)
    const daysPadding = 7
    const startDate = d3.timeDay.offset(minDate, -daysPadding)
    const endDate = d3.timeDay.offset(maxDate, daysPadding)

    // X scale (time)
    const xScale = d3.scaleTime()
      .domain([startDate, endDate])
      .range([0, width])

    // Y scale (tracks)
    const yScale = d3.scaleBand()
      .domain(tracks)
      .range([0, height])
      .padding(0.2)

    // Add X axis
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

    // Add Y axis (track labels)
    const yAxis = d3.axisLeft(yScale)
      .tickFormat(d => `Track ${d}`)

    svg.append("g")
      .attr("class", "y-axis")
      .call(yAxis)
      .selectAll("text")
      .style("font-size", "12px")
      .style("fill", "#374151")

    // Add grid lines
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
        .attr("class", "today-marker")
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

    // Create tooltip
    const tooltip = d3.select(this.element)
      .append("div")
      .attr("class", "absolute hidden bg-gray-900 text-white text-sm px-3 py-2 rounded-lg shadow-lg pointer-events-none z-50 max-w-xs")
      .style("transition", "opacity 0.15s")

    // Color scale based on status
    const statusColors = {
      unread: "#9ca3af",      // gray
      reading: "#3b82f6",     // blue
      completed: "#10b981",   // green
      abandoned: "#ef4444"    // red
    }

    // Draw book bars
    const bars = svg.selectAll(".book-bar")
      .data(booksWithDates)
      .enter()
      .append("g")
      .attr("class", "book-bar cursor-pointer")
      .attr("transform", d => `translate(${xScale(d.startDate)},${yScale(d.track)})`)

    // Background bar
    bars.append("rect")
      .attr("class", "bar-bg")
      .attr("width", d => Math.max(xScale(d.endDate) - xScale(d.startDate), 20))
      .attr("height", yScale.bandwidth())
      .attr("rx", 6)
      .attr("ry", 6)
      .style("fill", d => statusColors[d.status] || "#9ca3af")
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
      .style("fill", d => statusColors[d.status] || "#9ca3af")
      .style("opacity", 0.8)

    // Book title text
    bars.append("text")
      .attr("x", 8)
      .attr("y", yScale.bandwidth() / 2)
      .attr("dy", "0.35em")
      .style("fill", "#111827")
      .style("font-size", "12px")
      .style("font-weight", "500")
      .text(d => this.truncateTitle(d.title, xScale(d.endDate) - xScale(d.startDate) - 16))

    // Difficulty indicator
    bars.append("text")
      .attr("x", d => Math.max(xScale(d.endDate) - xScale(d.startDate), 20) - 8)
      .attr("y", yScale.bandwidth() / 2)
      .attr("dy", "0.35em")
      .attr("text-anchor", "end")
      .style("fill", "#6b7280")
      .style("font-size", "10px")
      .text(d => "★".repeat(d.difficulty))

    // Hover effects
    bars.on("mouseenter", (event, d) => {
      const bar = d3.select(event.currentTarget)
      bar.select(".bar-progress").style("opacity", 1)
      bar.select(".bar-bg").style("opacity", 0.3)

      const durationDays = Math.ceil((d.endDate - d.startDate) / (1000 * 60 * 60 * 24))

      tooltip
        .html(`
          <div class="font-semibold mb-1">${d.title}</div>
          <div class="text-gray-300 text-xs">${d.author || "Unknown author"}</div>
          <div class="mt-2 space-y-1 text-xs">
            <div><span class="text-gray-400">Pages:</span> ${d.total_pages}</div>
            <div><span class="text-gray-400">Progress:</span> ${d.progress}%</div>
            <div><span class="text-gray-400">Duration:</span> ${durationDays} days</div>
            <div><span class="text-gray-400">Est. time:</span> ${d.estimated_hours.toFixed(1)}h</div>
            <div><span class="text-gray-400">Status:</span> ${d.status}</div>
          </div>
        `)
        .classed("hidden", false)
        .style("left", `${event.offsetX + 10}px`)
        .style("top", `${event.offsetY + 10}px`)
    })

    bars.on("mouseleave", (event) => {
      const bar = d3.select(event.currentTarget)
      bar.select(".bar-progress").style("opacity", 0.8)
      bar.select(".bar-bg").style("opacity", 0.2)
      tooltip.classed("hidden", true)
    })

    bars.on("click", (event, d) => {
      window.location.href = `/books/${d.book_id}`
    })

    // Add legend
    this.renderLegend()
  }

  renderLegend() {
    const legendData = [
      { label: "Unread", color: "#9ca3af" },
      { label: "Reading", color: "#3b82f6" },
      { label: "Completed", color: "#10b981" },
      { label: "Abandoned", color: "#ef4444" }
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

  truncateTitle(title, maxWidth) {
    const charWidth = 7 // approximate pixels per character
    const maxChars = Math.floor(maxWidth / charWidth)

    if (title.length <= maxChars) return title
    if (maxChars < 4) return ""

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
