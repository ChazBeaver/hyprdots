.pragma library

function makeId() {
  return "t" + Date.now().toString(36) + Math.random().toString(36).substring(2, 8)
}

function squish(value) {
  if (value === undefined || value === null) return ""
  return String(value).replace(/\s+/g, " ").replace(/^\s+|\s+$/g, "")
}

function normalize(item) {
  if (!item || typeof item !== "object") return null
  var name = squish(item.name)
  if (name === "") return null
  var id = squish(item.id)
  if (id === "") id = makeId()
  return {
    id: id,
    name: name,
    description: squish(item.description),
    completed: item.completed === true
  }
}

function parse(raw) {
  var text = raw === undefined || raw === null ? "" : String(raw)
  if (squish(text) === "") return []
  var data
  try { data = JSON.parse(text) } catch (e) { return [] }
  var input = Array.isArray(data) ? data : (data && Array.isArray(data.todos) ? data.todos : [])
  var output = []
  var seen = {}
  for (var i = 0; i < input.length; i++) {
    var item = normalize(input[i])
    if (!item) continue
    if (seen[item.id]) item.id = makeId()
    seen[item.id] = true
    output.push(item)
  }
  return output
}

function serialize(items) {
  var output = []
  for (var i = 0; items && i < items.length; i++) {
    var item = normalize(items[i])
    if (item) output.push(item)
  }
  return JSON.stringify({ version: 2, todos: output }, null, 2) + "\n"
}
