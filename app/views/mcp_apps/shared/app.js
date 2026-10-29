/*
  The script that every MCP App template shares (McpTools::AppResource puts
  this file in place of its @include line). It talks to the host over
  postMessage (JSON-RPC 2.0), applies the host theme, reports the page size,
  and has the helpers the templates use. A template calls
  App.start({ name, render }), and render(data) draws the structuredContent
  of the tool result.
*/
var App = (function () {
  "use strict";

  var PROTOCOL_VERSION = "2026-01-26";
  var DAYS = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"];
  var DAY_LABELS = {
    monday: "Mon", tuesday: "Tue", wednesday: "Wed", thursday: "Thu",
    friday: "Fri", saturday: "Sat", sunday: "Sun"
  };
  var DAY_NAMES = {
    monday: "Monday", tuesday: "Tuesday", wednesday: "Wednesday", thursday: "Thursday",
    friday: "Friday", saturday: "Saturday", sunday: "Sunday"
  };
  var COLORS = 8;

  var nextId = 1;
  var pending = {};
  var host = window.parent;
  var renderData = function () {};

  // --- The postMessage bridge (JSON-RPC 2.0) ---------------------------------

  function send(message) {
    message.jsonrpc = "2.0";
    host.postMessage(message, "*");
  }

  function request(method, params) {
    var id = nextId++;
    send({ id: id, method: method, params: params });
    return new Promise(function (resolve, reject) {
      pending[id] = { resolve: resolve, reject: reject };
    });
  }

  function notify(method, params) {
    send({ method: method, params: params || {} });
  }

  function respond(id, result) {
    send({ id: id, result: result || {} });
  }

  window.addEventListener("message", function (event) {
    if (event.source !== host) return;
    var data = event.data;
    if (!data || data.jsonrpc !== "2.0") return;

    // A response to one of our requests.
    if (data.method === undefined && data.id !== undefined) {
      var waiting = pending[data.id];
      if (!waiting) return;
      delete pending[data.id];
      if (data.error) waiting.reject(new Error(data.error.message || "Request failed"));
      else waiting.resolve(data.result || {});
      return;
    }

    switch (data.method) {
      case "ui/notifications/tool-result":
        render(data.params || {});
        break;
      case "ui/notifications/tool-cancelled":
        showStatus("The tool call was cancelled.", false);
        break;
      case "ui/notifications/host-context-changed":
        applyHostContext(data.params || {});
        break;
      case "ui/resource-teardown":
      case "ping":
        if (data.id !== undefined) respond(data.id, {});
        break;
    }
  });

  // --- Theme -----------------------------------------------------------------

  function applyHostContext(context) {
    var root = document.documentElement;
    if (context.theme === "light" || context.theme === "dark") {
      root.setAttribute("data-theme", context.theme);
    }
    var variables = context.styles && context.styles.variables;
    if (variables) {
      Object.keys(variables).forEach(function (name) {
        if (name.indexOf("--") === 0 && variables[name]) root.style.setProperty(name, variables[name]);
      });
    }
    var fonts = context.styles && context.styles.css && context.styles.css.fonts;
    if (fonts && !document.getElementById("host-fonts")) {
      var style = document.createElement("style");
      style.id = "host-fonts";
      style.textContent = fonts;
      document.head.appendChild(style);
    }
  }

  // --- Size ------------------------------------------------------------------

  var lastHeight = 0;
  function reportSize() {
    var height = Math.ceil(document.documentElement.getBoundingClientRect().height);
    if (height === lastHeight) return;
    lastHeight = height;
    notify("ui/notifications/size-changed", {
      width: Math.ceil(document.documentElement.getBoundingClientRect().width),
      height: height
    });
  }

  // --- Times and dates -------------------------------------------------------

  // "09:05" to 545. Null for anything else.
  function minutes(hhmm) {
    if (typeof hhmm !== "string") return null;
    var parts = hhmm.split(":");
    if (parts.length !== 2) return null;
    var value = parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
    return isNaN(value) ? null : value;
  }

  // 12-hour time with no AM or PM, for a narrow block: "9:05".
  function shortClock(total) {
    var h = Math.floor(total / 60) % 24;
    var m = total % 60;
    return (h % 12 === 0 ? 12 : h % 12) + ":" + (m < 10 ? "0" : "") + m;
  }

  // 12-hour time: "9:05 AM". With short, a whole hour drops the minutes:
  // "1 PM".
  function clock(total, short) {
    var h = Math.floor(total / 60) % 24;
    var m = total % 60;
    var suffix = h < 12 ? " AM" : " PM";
    var h12 = h % 12 === 0 ? 12 : h % 12;
    if (short && m === 0) return h12 + suffix;
    return h12 + ":" + (m < 10 ? "0" : "") + m + suffix;
  }

  // A range: "9:00 – 9:50 AM", or "11:00 AM – 12:15 PM" when it crosses noon
  // or ends at midnight (24:00, from BusyBlocks).
  function range(start, end) {
    if (end < 1440 && (start < 720) === (end < 720)) return shortClock(start) + " – " + clock(end);
    return clock(start) + " – " + clock(end);
  }

  // "HH:MM" strings to a range. Null when a time is missing.
  function timeRange(begin, end) {
    var start = minutes(begin);
    var finish = minutes(end);
    return start === null || finish === null ? null : range(start, finish);
  }

  // "2026-12-14" to a local Date at noon, so no time zone moves the day.
  function parseDate(iso) {
    var parts = String(iso).split("-");
    if (parts.length !== 3) return null;
    return new Date(+parts[0], +parts[1] - 1, +parts[2], 12);
  }

  // "Mon, Dec 14". With weekday false: "Dec 14".
  function formatDate(iso, options) {
    var date = parseDate(iso);
    if (!date || isNaN(date)) return String(iso);
    var format = { month: "short", day: "numeric" };
    if (!options || options.weekday !== false) format.weekday = options && options.longWeekday ? "long" : "short";
    if (options && options.year) format.year = "numeric";
    return date.toLocaleDateString("en-US", format);
  }

  function plural(count, one, many) {
    return count + " " + (count === 1 ? one : (many || one + "s"));
  }

  // One color index for each course: "CHEM 1100-13E" and "CHEM 1100-15E" (a
  // lecture and its lab) get the same color.
  function colorPicker() {
    var colors = {};
    var count = 0;
    return function (code) {
      var key = String(code).replace(/-[^-\s]+$/, "");
      if (colors[key] === undefined) colors[key] = count++ % COLORS;
      return colors[key];
    };
  }

  // --- DOM -------------------------------------------------------------------

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
  }

  function append(parent) {
    for (var i = 1; i < arguments.length; i++) {
      if (arguments[i]) parent.appendChild(arguments[i]);
    }
    return parent;
  }

  function chips(values, className) {
    var list = el("ul", "chips");
    values.forEach(function (value) { list.appendChild(el("li", "chip" + (className ? " " + className : ""), value)); });
    return list;
  }

  function setHeader(title, summary) {
    document.getElementById("title").textContent = title;
    document.getElementById("summary").textContent = summary || "";
  }

  function clear() {
    var app = document.getElementById("app");
    app.textContent = "";
    return app;
  }

  function showStatus(text, isError) {
    var status = el("p", "status" + (isError ? " error" : ""), text);
    status.setAttribute("role", isError ? "alert" : "status");
    clear().appendChild(status);
    reportSize();
  }

  // What the advisory says about each term source (Catalog::Freshness), by key.
  var TERM_SOURCE_TEXT = {
    sections: {
      ended: "This term has ended, so WIT Calendar no longer refreshes its section data.",
      never: "The section data of this term has not refreshed from Banner yet.",
      last: "Section data last refreshed from Banner on "
    },
    finals: {
      ended: "This term has ended, so WIT Calendar no longer loads its finals schedule.",
      never: "WIT Calendar has not loaded the Registrar finals schedule of this term yet.",
      last: "The Registrar finals schedule was last loaded on "
    }
  };

  // The advisory (McpTools::BaseTool): not official, confirm with the program
  // director and advisor, and when the sections (or the finals) of the
  // result's term last refreshed. Catalog::Freshness lists the current and
  // future terms that have sections. Uids sort in time order, so a term newer
  // than a listed term has no data yet, and any other missing term has ended.
  function advisoryText(advisory, termUid) {
    if (!advisory) return null;
    var text = "WIT Calendar is not an official Wentworth service. Confirm your plan with your program " +
      "director and your academic advisor.";
    var sources = advisory.data_sources || [];
    var source = ["sections", "finals"].map(function (key) {
      return sources.filter(function (item) { return item.key === key && item.terms; })[0];
    }).filter(Boolean)[0];
    if (!source || !termUid) return text;

    var words = TERM_SOURCE_TEXT[source.key];
    var entry = source.terms.filter(function (term) { return term.term_uid === termUid; })[0];
    if (!entry) {
      var future = source.terms.some(function (term) { return term.term_uid < termUid; });
      return text + " " + (future ? words.never : words.ended);
    }
    if (!entry.last_refreshed_at) return text + " " + words.never;

    return text + " " + words.last +
      new Date(entry.last_refreshed_at).toLocaleString("en-US", {
        timeZone: "America/New_York", month: "short", day: "numeric", hour: "numeric", minute: "2-digit"
      }) + ".";
  }

  function advisory(data, termUid) {
    var text = advisoryText(data.advisory, termUid);
    return text ? el("p", "advisory", text) : null;
  }

  // --- Start -----------------------------------------------------------------

  function render(result) {
    if (result.isError) {
      var message = (result.content || []).map(function (item) { return item.text; }).filter(Boolean).join(" ");
      showStatus(message || "The tool returned an error.", true);
      return;
    }
    if (!result.structuredContent) {
      showStatus("The tool result has no data to show.", true);
      return;
    }
    renderData(result.structuredContent);
    reportSize();
  }

  function start(options) {
    renderData = options.render;

    if (typeof ResizeObserver === "function") {
      new ResizeObserver(reportSize).observe(document.documentElement);
    }

    request("ui/initialize", {
      protocolVersion: PROTOCOL_VERSION,
      appInfo: { name: options.name, version: "1.0.0" },
      appCapabilities: { availableDisplayModes: ["inline"] }
    }).then(function (result) {
      applyHostContext(result.hostContext || {});
      notify("ui/notifications/initialized", {});
      // A host can drop a size report that came before initialized.
      lastHeight = 0;
      reportSize();
    }).catch(function () {
      showStatus("The host did not start the view.", true);
    });
  }

  return {
    DAYS: DAYS,
    DAY_LABELS: DAY_LABELS,
    DAY_NAMES: DAY_NAMES,
    COLORS: COLORS,
    minutes: minutes,
    shortClock: shortClock,
    clock: clock,
    range: range,
    timeRange: timeRange,
    parseDate: parseDate,
    formatDate: formatDate,
    plural: plural,
    colorPicker: colorPicker,
    el: el,
    append: append,
    chips: chips,
    setHeader: setHeader,
    clear: clear,
    showStatus: showStatus,
    advisory: advisory,
    reportSize: reportSize,
    start: start
  };
})();
