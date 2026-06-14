const hazardTypes = {
  pothole: { label: "Pothole", color: "#ee5634", icon: "icon-record" },
  debris: { label: "Debris", color: "#e6bc00", icon: "icon-flag" },
  glass: { label: "Glass", color: "#2bb3c0", icon: "icon-warning" },
  water: { label: "Water", color: "#3b82f6", icon: "icon-warning" },
  blockedLane: { label: "Blocked Lane", color: "#e5484d", icon: "icon-warning" },
  construction: { label: "Construction", color: "#ff8a00", icon: "icon-warning" },
  noBikeLane: { label: "No Bike Lane", color: "#e5484d", icon: "icon-warning" },
  roughSurface: { label: "Rough Surface", color: "#ff8a00", icon: "icon-warning" },
  capturedPhoto: { label: "Captured Photo", color: "#ee5634", icon: "icon-camera" }
};

const titles = {
  map: "Hazard Map",
  record: "Record",
  rides: "Rides",
  profile: "Profile",
  recap: "Recap",
  pairing: "Pi Pairing"
};

const SUPABASE_CONFIG_STORAGE_KEY = "blindspot.supabase.config";
const SAN_JOSE_BOUNDS = {
  minLat: 37.326,
  maxLat: 37.35,
  minLng: -121.899,
  maxLng: -121.875
};

let hazards = [
  { id: "h1", type: "pothole", x: 36, y: 26, status: "Confirmed", confirmations: 12, age: "2h ago" },
  { id: "h2", type: "glass", x: 58, y: 40, status: "Confirmed", confirmations: 5, age: "6h ago" },
  { id: "h3", type: "construction", x: 72, y: 21, status: "Reported", confirmations: 1, age: "8h ago" },
  { id: "h4", type: "blockedLane", x: 30, y: 66, status: "Confirmed", confirmations: 9, age: "3h ago" },
  { id: "h5", type: "water", x: 68, y: 68, status: "Reported", confirmations: 1, age: "3h ago" }
];

let rides = [
  {
    id: "r1",
    date: "Jun 12, 2026",
    distance: "1.62",
    duration: "07:07",
    avg: "13.6",
    safety: 82,
    rating: 4,
    favorite: true,
    hazards: 2,
    potholes: 1,
    summary: "Protected crossings and clear pavement for most of the route, with one confirmed pothole near the north end.",
    ratingWord: "Good",
    score: 82,
    tags: ["green_lane", "pothole", "smooth_surface"],
    events: [
      { icon: "icon-flag", x: 36, y: 56 },
      { icon: "icon-warning", x: 67, y: 38 }
    ],
    photos: ["manual", "machine", "machine"]
  },
  {
    id: "r2",
    date: "Jun 9, 2026",
    distance: "1.81",
    duration: "09:08",
    avg: "12.1",
    safety: 67,
    rating: 3,
    favorite: false,
    hazards: 3,
    potholes: 1,
    summary: "Paint-only bike access with glass and debris flags. The route is rideable, but traffic exposure is higher.",
    ratingWord: "Fair",
    score: 67,
    tags: ["painted_lane", "glass", "debris", "hard_brake"],
    events: [
      { icon: "icon-flag", x: 29, y: 63 },
      { icon: "icon-warning", x: 58, y: 45 },
      { icon: "icon-warning", x: 71, y: 34 }
    ],
    photos: ["machine", "machine", "manual"]
  },
  {
    id: "r3",
    date: "Jun 5, 2026",
    distance: "1.16",
    duration: "04:15",
    avg: "16.1",
    safety: 91,
    rating: 0,
    favorite: false,
    hazards: 1,
    potholes: 0,
    summary: "Smooth surface and low hazard density. The app found no obvious potholes in the captured frames.",
    ratingWord: "Good",
    score: 91,
    tags: ["smooth_surface", "low_traffic", "no_potholes"],
    events: [
      { icon: "icon-flag", x: 48, y: 48 }
    ],
    photos: []
  }
];

let activeTab = "map";
let detailParent = null;
let currentRide = null;
let recordTimer = null;
let startedAt = 0;
let elapsedSeconds = 0;
let flaggedDuringRide = 0;
let sosTimer = null;
let sosCount = 8;
let bleLog = [
  "advertising started",
  "connected: BlindSpot-Pi",
  "rx ride_start -> ready"
];
let supabaseClient = null;
let supabaseChannel = null;
let supabaseConfig = null;
let syncBusy = false;
let syncDebounce = null;
let openRecapRideId = null;

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => Array.from(document.querySelectorAll(selector));
const clone = (value) => JSON.parse(JSON.stringify(value));
const seedHazards = clone(hazards);
const seedRides = clone(rides);

function icon(id) {
  return `<svg aria-hidden="true"><use href="#${id}"></use></svg>`;
}

function setTitle(screen) {
  $("#screenTitle").textContent = titles[screen] || "Blind Spot";
  $("#backButton").classList.toggle("is-hidden", !detailParent);
  $("#headerAction").classList.toggle("is-hidden", screen !== "map");
}

function showScreen(screen, options = {}) {
  $$(".screen-view").forEach((view) => {
    view.classList.toggle("active", view.dataset.screen === screen);
  });

  if (!options.keepTab) {
    activeTab = screen;
  }

  $$(".tab").forEach((tab) => {
    tab.classList.toggle("active", tab.dataset.tab === activeTab);
  });

  setTitle(screen);
}

function showTab(tab) {
  detailParent = null;
  openRecapRideId = null;
  activeTab = tab;
  showScreen(tab);
}

function showDetail(screen, parentTab) {
  detailParent = parentTab;
  showScreen(screen, { keepTab: true });
}

function toast(message) {
  const node = $("#toast");
  node.textContent = message;
  node.classList.add("show");
  window.clearTimeout(node._timer);
  node._timer = window.setTimeout(() => node.classList.remove("show"), 1700);
}

function openSheet(title, actions) {
  $("#sheetTitle").textContent = title;
  const container = $("#sheetActions");
  container.innerHTML = "";
  actions.forEach((action) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `sheet-action${action.danger ? " danger" : ""}`;
    button.textContent = action.label;
    button.addEventListener("click", () => {
      closeSheet();
      action.onClick();
    });
    container.appendChild(button);
  });
  $("#actionSheet").classList.remove("hidden");
}

function closeSheet() {
  $("#actionSheet").classList.add("hidden");
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function escapeAttribute(value) {
  return escapeHtml(value).replaceAll("`", "&#096;");
}

function getHazardType(type) {
  return hazardTypes[type] || hazardTypes.capturedPhoto;
}

function normalizeHazardType(type) {
  const value = String(type || "").trim();
  const normalized = value
    .replace(/[-_\s]+([a-z])/g, (_, letter) => letter.toUpperCase())
    .replace(/^[A-Z]/, (letter) => letter.toLowerCase());
  return hazardTypes[normalized] ? normalized : "capturedPhoto";
}

function toSnakeHazardType(type) {
  return String(type).replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}

function coordinateToScreen(lat, lng) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return null;
  }
  const x = ((lng - SAN_JOSE_BOUNDS.minLng) / (SAN_JOSE_BOUNDS.maxLng - SAN_JOSE_BOUNDS.minLng)) * 100;
  const y = (1 - ((lat - SAN_JOSE_BOUNDS.minLat) / (SAN_JOSE_BOUNDS.maxLat - SAN_JOSE_BOUNDS.minLat))) * 100;
  return { x: clamp(Math.round(x), 8, 92), y: clamp(Math.round(y), 12, 82) };
}

function screenToCoordinate(x, y) {
  const lng = SAN_JOSE_BOUNDS.minLng + (clamp(x, 0, 100) / 100) * (SAN_JOSE_BOUNDS.maxLng - SAN_JOSE_BOUNDS.minLng);
  const lat = SAN_JOSE_BOUNDS.minLat + (1 - clamp(y, 0, 100) / 100) * (SAN_JOSE_BOUNDS.maxLat - SAN_JOSE_BOUNDS.minLat);
  return { lat, lng };
}

function seededPosition(seed) {
  let hash = 0;
  for (const char of String(seed)) {
    hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  }
  return {
    x: 18 + (hash % 65),
    y: 18 + ((hash >>> 8) % 56)
  };
}

function numberFrom(...values) {
  for (const value of values) {
    if (value === null || value === undefined || value === "") continue;
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return 0;
}

function arrayFrom(value) {
  if (Array.isArray(value)) return value.filter(Boolean);
  if (value && typeof value === "object") return Object.values(value).filter(Boolean);
  if (typeof value === "string" && value.trim()) return [value.trim()];
  return [];
}

function unique(values) {
  return Array.from(new Set(values.map((value) => String(value).trim()).filter(Boolean)));
}

function formatRideDate(value) {
  const date = value ? new Date(value) : new Date();
  if (Number.isNaN(date.getTime())) return "Unknown date";
  return new Intl.DateTimeFormat("en-US", { month: "short", day: "numeric", year: "numeric" }).format(date);
}

function formatMilesFromMeters(meters) {
  return (Math.max(0, meters) / 1609.344).toFixed(2);
}

function formatMphFromMps(mps) {
  return (Math.max(0, mps) * 2.236936).toFixed(1);
}

function getStoredSupabaseConfig() {
  const runtime = window.BLINDSPOT_SUPABASE_CONFIG;
  if (runtime?.url && runtime?.publishableKey) {
    return {
      url: runtime.url.trim(),
      publishableKey: runtime.publishableKey.trim()
    };
  }

  try {
    const stored = JSON.parse(localStorage.getItem(SUPABASE_CONFIG_STORAGE_KEY) || "null");
    if (stored?.url && stored?.publishableKey) {
      return {
        url: stored.url.trim(),
        publishableKey: stored.publishableKey.trim()
      };
    }
  } catch {
    localStorage.removeItem(SUPABASE_CONFIG_STORAGE_KEY);
  }
  return null;
}

function setSyncStatus(mode, message) {
  const label = $("#supabaseStateLabel");
  const statusLine = $("#supabaseStatusLine");
  const syncText = $("#syncStatusText");
  const dot = $("#syncDot");
  if (label) {
    label.textContent = mode === "live" ? "Live" : mode === "loading" ? "Syncing" : mode === "error" ? "Error" : "Mock";
  }
  if (statusLine) statusLine.textContent = message;
  if (syncText) syncText.textContent = message;
  if (dot) {
    dot.classList.toggle("live", mode === "live");
    dot.classList.toggle("error", mode === "error");
  }
}

function restoreSupabaseForm() {
  const config = getStoredSupabaseConfig();
  if ($("#supabaseUrlInput") && config) {
    $("#supabaseUrlInput").value = config.url;
    $("#supabaseKeyInput").value = config.publishableKey;
  }
  setSyncStatus(config ? "loading" : "mock", config ? "Ready to sync" : "Mock data");
}

async function connectSupabaseFromForm() {
  const url = $("#supabaseUrlInput").value.trim();
  const publishableKey = $("#supabaseKeyInput").value.trim();
  if (!url || !publishableKey) {
    setSyncStatus("error", "Enter URL and key");
    return;
  }
  if (publishableKey.startsWith("sb_secret_") || publishableKey.toLowerCase().includes("service_role")) {
    setSyncStatus("error", "Use a publishable key, not a secret key");
    return;
  }
  localStorage.setItem(SUPABASE_CONFIG_STORAGE_KEY, JSON.stringify({ url, publishableKey }));
  await initSupabase();
}

async function initSupabase() {
  supabaseConfig = getStoredSupabaseConfig();
  if (!supabaseConfig) {
    setSyncStatus("mock", "Mock data");
    return;
  }
  if (!window.supabase?.createClient) {
    setSyncStatus("error", "Supabase library unavailable");
    return;
  }
  supabaseClient = window.supabase.createClient(supabaseConfig.url, supabaseConfig.publishableKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false
    }
  });
  setSyncStatus("loading", "Syncing from Supabase");
  await syncFromSupabase();
  subscribeSupabaseRealtime();
}

function clearSupabaseConfig() {
  if (supabaseClient && supabaseChannel) {
    supabaseClient.removeChannel(supabaseChannel);
  }
  localStorage.removeItem(SUPABASE_CONFIG_STORAGE_KEY);
  supabaseConfig = null;
  supabaseClient = null;
  supabaseChannel = null;
  hazards = clone(seedHazards);
  rides = clone(seedRides);
  renderHazards();
  renderRides();
  setSyncStatus("mock", "Mock data");
  toast("Supabase config cleared");
}

async function selectTable(table, applyQuery, options = {}) {
  if (!supabaseClient) return [];
  let query = supabaseClient.from(table).select("*");
  if (applyQuery) query = applyQuery(query);
  const { data, error } = await query;
  if (error) {
    if (options.required) {
      throw new Error(`${table}: ${error.message}`);
    }
    console.warn(`Supabase ${table} skipped:`, error.message);
    return [];
  }
  return data || [];
}

async function syncFromSupabase() {
  if (!supabaseClient || syncBusy) return;
  syncBusy = true;
  setSyncStatus("loading", "Syncing from Supabase");
  try {
    await Promise.all([
      loadSupabaseRides(),
      loadSupabaseHazards()
    ]);
    setSyncStatus("live", `Live: ${rides.length} rides, ${hazards.length} hazards`);
    if (openRecapRideId) openRecap(openRecapRideId);
  } catch (error) {
    console.warn("Supabase sync failed:", error);
    setSyncStatus("error", error.message || "Supabase sync failed");
  } finally {
    syncBusy = false;
  }
}

function scheduleSupabaseSync() {
  window.clearTimeout(syncDebounce);
  syncDebounce = window.setTimeout(syncFromSupabase, 500);
}

function subscribeSupabaseRealtime() {
  if (!supabaseClient) return;
  if (supabaseChannel) {
    supabaseClient.removeChannel(supabaseChannel);
  }
  supabaseChannel = supabaseClient.channel("blindspot-phone-demo");
  ["rides", "photos", "automated_photos", "ai_summary", "hazards", "ride_events"].forEach((table) => {
    supabaseChannel.on(
      "postgres_changes",
      { event: "*", schema: "public", table },
      scheduleSupabaseSync
    );
  });
  supabaseChannel.subscribe((status) => {
    if (status === "SUBSCRIBED") {
      setSyncStatus("live", `Live: ${rides.length} rides, ${hazards.length} hazards`);
    }
  });
}

async function loadSupabaseHazards() {
  const hazardRows = await selectTable("hazards", (query) =>
    query.order("first_reported_at", { ascending: false }).limit(500)
  );
  if (hazardRows.length) {
    hazards = hazardRows.map(hazardFromSupabaseRow);
    renderHazards();
    return;
  }

  const manualPhotos = await selectTable("photos", (query) =>
    query.order("captured_at", { ascending: false }).limit(100)
  );
  const photoHazards = manualPhotos
    .filter((row) => Number.isFinite(Number(row.lat)) && Number.isFinite(Number(row.lng)))
    .map((row) => photoHazardFromSupabaseRow(row));
  hazards = photoHazards;
  renderHazards();
}

async function loadSupabaseRides() {
  const rideRows = await selectTable(
    "rides",
    (query) => query.order("started_at", { ascending: false }).limit(50),
    { required: true }
  );
  const [summaryRows, manualPhotoRows, machinePhotoRows, eventRows] = await Promise.all([
    selectTable("ai_summary", (query) => query.order("created_at", { ascending: false }).limit(100)),
    selectTable("photos", (query) => query.order("captured_at", { ascending: false }).limit(300)),
    selectTable("automated_photos", (query) => query.order("captured_at", { ascending: false }).limit(300)),
    selectTable("ride_events", (query) => query.order("occurred_at", { ascending: true }).limit(500))
  ]);

  const summariesByRide = latestByRide(summaryRows);
  const photosByRide = groupByRide([
    ...manualPhotoRows.map((row) => ({ ...row, isMachine: false })),
    ...machinePhotoRows.map((row) => ({ ...row, isMachine: true }))
  ]);
  const eventsByRide = groupByRide(eventRows);

  rides = rideRows.map((row) => rideFromSupabaseRow(
    row,
    summariesByRide.get(String(row.id)),
    photosByRide.get(String(row.id)) || [],
    eventsByRide.get(String(row.id)) || []
  ));
  renderRides();
}

function groupByRide(rows) {
  const grouped = new Map();
  rows.forEach((row) => {
    const rideId = String(row.ride_id || "");
    if (!rideId) return;
    if (!grouped.has(rideId)) grouped.set(rideId, []);
    grouped.get(rideId).push(row);
  });
  return grouped;
}

function latestByRide(rows) {
  const grouped = new Map();
  rows.forEach((row) => {
    const rideId = String(row.ride_id || "");
    if (!rideId || row.summary_type && row.summary_type !== "ride") return;
    if (!grouped.has(rideId)) grouped.set(rideId, row);
  });
  return grouped;
}

function hazardFromSupabaseRow(row) {
  const position = coordinateToScreen(Number(row.lat), Number(row.lng)) || seededPosition(row.id);
  return {
    id: String(row.id),
    type: normalizeHazardType(row.type),
    x: position.x,
    y: position.y,
    lat: Number(row.lat),
    lng: Number(row.lng),
    status: titleCase(row.status || "reported"),
    confirmations: Number(row.confirm_count || 1),
    age: relativeAge(row.last_confirmed_at || row.first_reported_at)
  };
}

function photoHazardFromSupabaseRow(row) {
  const position = coordinateToScreen(Number(row.lat), Number(row.lng)) || seededPosition(row.id);
  return {
    id: String(row.id),
    type: "capturedPhoto",
    x: position.x,
    y: position.y,
    lat: Number(row.lat),
    lng: Number(row.lng),
    status: "Captured",
    confirmations: 1,
    age: relativeAge(row.captured_at || row.created_at)
  };
}

function rideFromSupabaseRow(row, summary, photoRows, eventRows) {
  const distanceMeters = numberFrom(row.distance_meters, row.distance_m, summary?.distance_m, summary?.metrics?.distance_m);
  const durationSeconds = numberFrom(row.duration_seconds, row.duration_s, summary?.duration_s, summary?.metrics?.duration_s);
  const avgSpeed = numberFrom(row.avg_speed, durationSeconds > 0 ? distanceMeters / durationSeconds : 0);
  const score = Math.round(numberFrom(row.safety_score, row.accessibility_score, summary?.accessibility_score, 0));
  const ratingWord = titleCase(row.accessibility_rating || summary?.accessibility_rating || (score >= 80 ? "good" : score >= 50 ? "fair" : "poor"));
  const tags = unique([
    ...arrayFrom(row.accessibility_labels),
    ...arrayFrom(row.accessibility_map_tags),
    ...arrayFrom(row.road_hazards),
    ...arrayFrom(summary?.labels),
    ...arrayFrom(summary?.road_hazards),
    ...arrayFrom(summary?.recommended_map_tags)
  ]).slice(0, 8);
  const photos = photoRows
    .filter((photo) => photo.storage_url)
    .map((photo) => ({
      kind: photo.isMachine ? "machine" : "manual",
      url: photo.storage_url
    }));
  const events = eventRows.length
    ? eventRows.map((event, index) => eventFromSupabaseRow(event, index))
    : photos.slice(0, 3).map((photo, index) => ({
      icon: photo.kind === "machine" ? "icon-camera" : "icon-flag",
      ...seededPosition(`${row.id}-${index}`)
    }));

  return {
    id: String(row.id),
    date: formatRideDate(row.started_at || row.created_at),
    distance: formatMilesFromMeters(distanceMeters),
    duration: formatDuration(Math.round(durationSeconds)),
    avg: formatMphFromMps(avgSpeed),
    safety: score || 0,
    rating: Number(row.rating || 0),
    favorite: Boolean(row.favorite),
    hazards: eventRows.length || Number(row.photo_count || photos.length || 0),
    potholes: Number(row.pothole_count ?? summary?.pothole_count ?? 0),
    summary: summary?.summary || row.accessibility_summary || row.qwen_summary?.summary || "Synced ride from Supabase.",
    ratingWord,
    score,
    tags: tags.length ? tags : ["synced"],
    events,
    photos
  };
}

function eventFromSupabaseRow(row, index) {
  const position = coordinateToScreen(Number(row.lat), Number(row.lng)) || seededPosition(`${row.id || row.ride_id}-${index}`);
  return {
    icon: row.type === "crash" || row.type === "impact" ? "icon-warning" : "icon-flag",
    x: position.x,
    y: position.y
  };
}

function relativeAge(value) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) return "synced";
  const seconds = Math.max(1, Math.round((Date.now() - date.getTime()) / 1000));
  if (seconds < 60) return "now";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 48) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}

function titleCase(value) {
  return String(value || "")
    .replaceAll("_", " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

async function saveHazardToSupabase(hazard) {
  if (!supabaseClient) return;
  const coord = Number.isFinite(hazard.lat) && Number.isFinite(hazard.lng)
    ? { lat: hazard.lat, lng: hazard.lng }
    : screenToCoordinate(hazard.x, hazard.y);
  const row = {
    lat: coord.lat,
    lng: coord.lng,
    type: toSnakeHazardType(hazard.type),
    severity: "moderate",
    status: "reported",
    confirm_count: 1,
    first_reported_at: new Date().toISOString()
  };
  const { error } = await supabaseClient.from("hazards").insert(row);
  if (error) {
    console.warn("Hazard insert skipped:", error.message);
    toast("Saved locally");
    return;
  }
  await syncFromSupabase();
}

function renderHazards() {
  const pins = $("#hazardPins");
  pins.innerHTML = hazards.map((hazard) => {
    const type = getHazardType(hazard.type);
    return `
      <button class="map-pin" type="button" data-hazard="${escapeAttribute(hazard.id)}" style="left:${hazard.x}%;top:${hazard.y}%;--pin-color:${type.color}" aria-label="${escapeAttribute(type.label)}">
        ${icon(type.icon)}
      </button>
    `;
  }).join("");

  $("#hazardList").innerHTML = hazards.map((hazard) => {
    const type = getHazardType(hazard.type);
    return `
      <button class="hazard-row" type="button" data-hazard="${escapeAttribute(hazard.id)}">
        <span class="hazard-dot" style="--pin-color:${type.color}">${icon(type.icon)}</span>
        <span>
          <strong>${escapeHtml(type.label)}</strong>
          <small>${escapeHtml(hazard.status)} - ${escapeHtml(hazard.confirmations)} confirms - ${escapeHtml(hazard.age)}</small>
        </span>
        <span class="pill">${escapeHtml(hazard.status)}</span>
      </button>
    `;
  }).join("");

  $("#hazardCount").textContent = hazards.length;
}

function addHazardAt(x, y) {
  openSheet("Add a hazard here", Object.keys(hazardTypes).map((key) => ({
    label: hazardTypes[key].label,
    onClick: async () => {
      const coord = screenToCoordinate(x, y);
      const hazard = {
        id: `h${Date.now()}`,
        type: key,
        x,
        y,
        lat: coord.lat,
        lng: coord.lng,
        status: "Reported",
        confirmations: 1,
        age: "now"
      };
      hazards.unshift(hazard);
      renderHazards();
      toast(`${hazardTypes[key].label} added`);
      await saveHazardToSupabase(hazard);
    }
  })));
}

function openHazardActions(id) {
  const hazard = hazards.find((item) => item.id === id);
  if (!hazard) return;
  const type = hazardTypes[hazard.type];
  openSheet(type.label, [
    {
      label: "Report",
      onClick: () => toast("Report draft opened")
    },
    {
      label: "Confirm still here",
      onClick: () => {
        hazard.status = "Confirmed";
        hazard.confirmations += 1;
        hazard.age = "now";
        renderHazards();
        toast("Hazard confirmed");
      }
    },
    {
      label: "Delete",
      danger: true,
      onClick: () => {
        hazards = hazards.filter((item) => item.id !== id);
        renderHazards();
        toast("Hazard deleted");
      }
    }
  ]);
}

function renderRides() {
  $("#rideList").innerHTML = rides.map((ride) => `
    <article class="ride-row">
      <div class="ride-row-header">
        <button class="ride-row-title" data-open-ride="${escapeAttribute(ride.id)}" type="button">
          ${ride.favorite ? '<span class="favorite-star" aria-hidden="true">&#9733;</span>' : ""}
          <strong>${escapeHtml(ride.date)}</strong>
        </button>
        ${safetyBadge(ride.safety)}
      </div>
      <button class="row-stats" data-open-ride="${escapeAttribute(ride.id)}" type="button">
        <span class="row-stat"><strong>${escapeHtml(ride.distance)}</strong><span>DISTANCE</span></span>
        <span class="row-stat"><strong>${escapeHtml(ride.duration)}</strong><span>DURATION</span></span>
        <span class="row-stat"><strong>${escapeHtml(ride.avg)}</strong><span>AVG</span></span>
      </button>
      <div class="ride-row-actions">
        <button class="icon-button" type="button" data-favorite="${escapeAttribute(ride.id)}" aria-label="Favorite ride">${icon("icon-star")}</button>
        <button class="icon-button" type="button" data-delete-ride="${escapeAttribute(ride.id)}" aria-label="Delete ride">${icon("icon-trash")}</button>
        <span class="stars" aria-label="${ride.rating || 0} star rating">${renderStars(ride.rating, ride.id, false)}</span>
      </div>
    </article>
  `).join("");
}

function safetyBadge(score) {
  const displayScore = Number.isFinite(Number(score)) ? Number(score) : 0;
  const color = displayScore >= 80 ? "#30a46c" : displayScore >= 60 ? "#ff8a00" : "#e5484d";
  return `
    <span class="safety-badge" style="--badge-color:${color}">
      ${icon("icon-shield")}
      ${displayScore || "-"}
    </span>
  `;
}

function renderStars(rating, rideId, large) {
  let html = "";
  for (let i = 1; i <= 5; i += 1) {
    html += `
      <button class="star-button ${i <= rating ? "filled" : ""}" type="button" data-rate="${escapeAttribute(`${rideId}:${i}`)}" aria-label="${i} stars">
        ${icon("icon-star")}
      </button>
    `;
  }
  return html;
}

function openRecap(id) {
  const ride = rides.find((item) => item.id === id);
  if (!ride) return;
  openRecapRideId = id;
  const scoreColor = ride.score >= 80 ? "#30a46c" : ride.score >= 50 ? "#ff8a00" : "#e5484d";
  $("#recapContent").innerHTML = `
    <div class="card route-card">
      <div class="road road-a"></div>
      <div class="road road-b"></div>
      <div class="route-line"></div>
      ${ride.events.map((event) => `<span class="event-marker" style="left:${event.x}%;top:${event.y}%">${icon(event.icon)}</span>`).join("")}
    </div>

    <div class="card">
      <div class="stat-grid">
        <div class="stat-tile"><strong>${escapeHtml(ride.distance)}</strong><span>mi</span><small>DISTANCE</small></div>
        <div class="stat-tile"><strong>${escapeHtml(ride.duration)}</strong><small>DURATION</small></div>
        <div class="stat-tile"><strong>${escapeHtml(ride.avg)}</strong><span>mph</span><small>AVG SPEED</small></div>
        <div class="stat-tile"><strong>${escapeHtml(ride.hazards)}</strong><small>HAZARDS</small></div>
      </div>
    </div>

    <div class="card">
      <div class="section-heading">
        <span>AI RIDE SUMMARY</span>
        <span class="ai-badge" style="--badge-color:${scoreColor}">${escapeHtml(ride.ratingWord)} ${escapeHtml(ride.score || "-")}</span>
      </div>
      <p class="summary-text">${escapeHtml(ride.summary)}</p>
      ${ride.potholes ? `<p class="muted">${ride.potholes} pothole${ride.potholes === 1 ? "" : "s"} detected</p>` : ""}
      <div class="chips">${ride.tags.map((tag) => `<span class="chip">${escapeHtml(String(tag).replaceAll("_", " "))}</span>`).join("")}</div>
    </div>

    <div class="card">
      <div class="section-heading"><span>RATE THIS RIDE</span></div>
      <div class="stars">${renderStars(ride.rating, ride.id, true)}</div>
    </div>

    <div class="card">
      <div class="section-heading">
        <span>PHOTOS</span>
        <strong>${ride.photos.length}</strong>
      </div>
      <div class="photo-grid">
        ${(ride.photos.length ? ride.photos : ["empty", "empty", "empty"]).map((photo) => `
          <span class="photo-cell">
            ${typeof photo === "object" && photo.url
              ? `<img src="${escapeAttribute(photo.url)}" alt="">`
              : icon("icon-camera")}
            ${photo === "machine" || photo?.kind === "machine" ? `<span class="machine-dot">${icon("icon-camera")}</span>` : ""}
          </span>
        `).join("")}
      </div>
    </div>
  `;
  showDetail("recap", "rides");
}

function startRide() {
  currentRide = {
    id: `r${Date.now()}`,
    date: "Today",
    events: [],
    photos: ["manual"]
  };
  startedAt = Date.now();
  elapsedSeconds = 0;
  flaggedDuringRide = 0;
  $("#recordIdle").classList.add("hidden");
  $("#recordingPanel").classList.remove("hidden");
  $("#activeRideStatus").textContent = currentRide.id.slice(0, 8);
  addBleLine(`tx ride_started ${currentRide.id.slice(0, 8)}`);
  updateTelemetry();
  recordTimer = window.setInterval(updateTelemetry, 1000);
  toast("Ride started");
}

function stopRide() {
  if (!currentRide) return;
  window.clearInterval(recordTimer);
  const miles = Math.max(0.18, elapsedSeconds * 0.0034);
  const ride = {
    id: currentRide.id,
    date: "Today",
    distance: miles.toFixed(2),
    duration: formatDuration(elapsedSeconds),
    avg: (miles / Math.max(elapsedSeconds / 3600, 0.04)).toFixed(1),
    safety: Math.max(58, 91 - flaggedDuringRide * 7),
    rating: 0,
    favorite: false,
    hazards: flaggedDuringRide,
    potholes: currentRide.events.filter((event) => event === "pothole").length,
    summary: flaggedDuringRide
      ? "The Pi captured ride photos and flagged hazards for review. The recap is ready for rating."
      : "Clean short ride with no hazards flagged during the demo session.",
    ratingWord: flaggedDuringRide ? "Fair" : "Good",
    score: Math.max(58, 91 - flaggedDuringRide * 7),
    tags: flaggedDuringRide ? ["manual_flags", "pi_photos", "review_needed"] : ["smooth_surface", "no_flags"],
    events: flaggedDuringRide
      ? [{ icon: "icon-flag", x: 42, y: 52 }, { icon: "icon-warning", x: 65, y: 39 }].slice(0, Math.max(1, Math.min(2, flaggedDuringRide)))
      : [{ icon: "icon-bike", x: 50, y: 49 }],
    photos: currentRide.photos
  };
  rides.unshift(ride);
  currentRide = null;
  $("#recordIdle").classList.remove("hidden");
  $("#recordingPanel").classList.add("hidden");
  $("#activeRideStatus").textContent = "-";
  renderRides();
  openRecap(ride.id);
  toast("Ride saved");
}

function updateTelemetry() {
  elapsedSeconds = Math.floor((Date.now() - startedAt) / 1000);
  const speed = 12 + Math.sin(elapsedSeconds / 3) * 2.4;
  const distance = elapsedSeconds * 0.0034;
  const peak = 1 + flaggedDuringRide * 0.7 + Math.max(0, Math.sin(elapsedSeconds / 4)) * 0.4;
  $("#speedStat").textContent = speed.toFixed(1);
  $("#timeStat").textContent = formatDuration(elapsedSeconds);
  $("#distanceStat").textContent = distance.toFixed(2);
  $("#peakGStat").textContent = peak.toFixed(1);
}

function flagHazard(type) {
  if (!currentRide) return;
  flaggedDuringRide += 1;
  currentRide.events.push(type);
  currentRide.photos.push("manual");
  const note = $("#flagNote");
  note.textContent = `${hazardTypes[type].label} saved`;
  note.classList.add("show");
  window.clearTimeout(note._timer);
  note._timer = window.setTimeout(() => note.classList.remove("show"), 1500);
  toast("Photo attached to ride");
}

function simulateCrash() {
  sosCount = 8;
  $("#sosOverlay").classList.remove("hidden");
  $("#sosTitle").textContent = "CRASH DETECTED";
  $("#sosCopy").textContent = "Sending SOS in";
  $("#sosCountdown").textContent = sosCount;
  $("#sosCountdown").style.display = "block";
  $("#sosContact").textContent = "Will alert: Alex - (555) 910-2211";
  $("#cancelSosButton").textContent = "I'M OK - CANCEL";
  window.clearInterval(sosTimer);
  sosTimer = window.setInterval(() => {
    sosCount -= 1;
    $("#sosCountdown").textContent = sosCount;
    if (sosCount <= 0) {
      window.clearInterval(sosTimer);
      $("#sosTitle").textContent = "SOS SENT";
      $("#sosCopy").textContent = "Emergency contact was notified.";
      $("#sosCountdown").style.display = "none";
      $("#sosContact").textContent = "(Mock demo - no message was sent.)";
      $("#cancelSosButton").textContent = "DISMISS";
      addBleLine("crash_sos countdown completed");
    }
  }, 1000);
}

function dismissSos() {
  window.clearInterval(sosTimer);
  $("#sosOverlay").classList.add("hidden");
  addBleLine("crash_sos dismissed");
}

function formatDuration(seconds) {
  const min = Math.floor(seconds / 60).toString().padStart(2, "0");
  const sec = Math.floor(seconds % 60).toString().padStart(2, "0");
  return `${min}:${sec}`;
}

function addBleLine(line) {
  bleLog.unshift(line);
  bleLog = bleLog.slice(0, 6);
  renderBleLog();
}

function renderBleLog() {
  $("#bleLog").innerHTML = bleLog.map((line) => `<span>${line}</span>`).join("");
}

function attachEvents() {
  $$(".tab").forEach((tab) => {
    tab.addEventListener("click", () => showTab(tab.dataset.tab));
  });

  $("#backButton").addEventListener("click", () => {
    const target = detailParent || activeTab;
    detailParent = null;
    showTab(target);
  });

  $("#headerAction").addEventListener("click", () => addHazardAt(52, 48));
  $("#addHazardButton").addEventListener("click", (event) => {
    event.stopPropagation();
    addHazardAt(52, 48);
  });

  $("#hazardMap").addEventListener("click", (event) => {
    if (event.target.closest("button")) return;
    const rect = event.currentTarget.getBoundingClientRect();
    const x = Math.min(92, Math.max(8, ((event.clientX - rect.left) / rect.width) * 100));
    const y = Math.min(82, Math.max(12, ((event.clientY - rect.top) / rect.height) * 100));
    addHazardAt(Math.round(x), Math.round(y));
  });

  document.addEventListener("click", (event) => {
    const hazardButton = event.target.closest("[data-hazard]");
    if (hazardButton) openHazardActions(hazardButton.dataset.hazard);

    const rideButton = event.target.closest("[data-open-ride]");
    if (rideButton) openRecap(rideButton.dataset.openRide);

    const favorite = event.target.closest("[data-favorite]");
    if (favorite) {
      const ride = rides.find((item) => item.id === favorite.dataset.favorite);
      if (ride) ride.favorite = !ride.favorite;
      renderRides();
    }

    const deleteRide = event.target.closest("[data-delete-ride]");
    if (deleteRide) {
      rides = rides.filter((item) => item.id !== deleteRide.dataset.deleteRide);
      renderRides();
      toast("Ride deleted");
    }

    const rate = event.target.closest("[data-rate]");
    if (rate) {
      const [rideId, value] = rate.dataset.rate.split(":");
      const ride = rides.find((item) => item.id === rideId);
      if (ride) ride.rating = Number(value);
      renderRides();
      if (detailParent) openRecap(rideId);
      toast("Rating saved");
    }
  });

  $("#startRideButton").addEventListener("click", startRide);
  $("#stopRideButton").addEventListener("click", stopRide);
  $("#flagButton").addEventListener("click", () => {
    openSheet("Flag a hazard", Object.keys(hazardTypes).map((key) => ({
      label: hazardTypes[key].label,
      onClick: () => flagHazard(key)
    })));
  });
  $("#simulateCrashButton").addEventListener("click", simulateCrash);
  $("#cancelSosButton").addEventListener("click", dismissSos);

  $("#pairingCard").addEventListener("click", () => showDetail("pairing", "profile"));
  $("#pairingToggle").addEventListener("change", (event) => {
    const on = event.target.checked;
    $("#advertisingStatus").textContent = on ? "Yes" : "No";
    $("#advertisingStatus").classList.toggle("ok", on);
    $("#pairingSummary").textContent = on ? "Advertising" : "Off";
    addBleLine(on ? "advertising started" : "advertising stopped");
  });
  $("#simulatePiCommand").addEventListener("click", () => {
    const command = currentRide ? "ride_stop" : "ride_start";
    $("#lastCommandStatus").textContent = command;
    $("#lastResponseStatus").textContent = currentRide ? "finish requested" : "ride id issued";
    addBleLine(`rx ${command} -> ok`);
    toast("Pi command received");
  });
  $("#connectSupabaseButton").addEventListener("click", () => {
    connectSupabaseFromForm();
  });
  $("#clearSupabaseButton").addEventListener("click", clearSupabaseConfig);
  $("#syncNowButton").addEventListener("click", () => {
    if (supabaseClient) {
      syncFromSupabase();
    } else {
      showTab("profile");
      toast("Add Supabase config");
    }
  });
  $("#chooseContactButton").addEventListener("click", () => toast("Contact selected"));
  $("#sheetCancel").addEventListener("click", closeSheet);
  $("#actionSheet").addEventListener("click", (event) => {
    if (event.target.id === "actionSheet") closeSheet();
  });
}

renderHazards();
renderRides();
renderBleLog();
attachEvents();
restoreSupabaseForm();
initSupabase();
setTitle("map");
