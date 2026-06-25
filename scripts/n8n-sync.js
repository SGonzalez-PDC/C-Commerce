#!/usr/bin/env node
/*
 * n8n-sync.js
 * Despliega una carpeta de workflows n8n a una instancia via API REST.
 * - Reemplaza valores por entorno (URLs, nombres de BD) segun envs/<env>.json.
 * - Hace upsert: PUT si el workflow ya existe (por nombre, conserva su id),
 *   POST si es nuevo.
 * - Reescribe las referencias entre workflows (executeWorkflow / toolWorkflow)
 *   usando el mapa nombre -> id REAL del entorno destino, para que los nodos
 *   queden enlazados sin importar que id traia el archivo.
 * - Remapea credenciales por nombre si el env define el mapeo.
 *
 * Uso:
 *   node scripts/n8n-sync.js --env dev [--dry-run] [--activate] [--only "Nombre"]
 *
 * Credenciales de conexion (NO van al repo): variables de entorno
 *   N8N_URL       base, ej. https://n8n.midominio.com
 *   N8N_API_KEY   API key personal de esa instancia
 * En local se leen de un archivo .env (ver .env.example). En CI vienen de
 * los Secrets del GitHub Environment.
 */

const fs = require("fs");
const path = require("path");

// ---- args ----
const args = process.argv.slice(2);
function flag(name) { return args.includes("--" + name); }
function opt(name, def) { const i = args.indexOf("--" + name); return i >= 0 ? args[i + 1] : def; }

const ENV = opt("env", "dev");
const DRY = flag("dry-run");
const ACTIVATE = flag("activate");
const ONLY = opt("only", null);
const ROOT = path.resolve(__dirname, "..");

// ---- .env loader (simple, sin dependencias) ----
// Carga .env y, si existe, .env.<entorno> (este ultimo tiene prioridad). En CI no
// hay archivos .env: las variables vienen del environment del job.
function loadDotEnvFile(p) {
  if (!fs.existsSync(p)) return;
  for (const line of fs.readFileSync(p, "utf8").split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);
    if (m) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
}
const ENV_EARLY = (() => { const i = process.argv.indexOf("--env"); return i >= 0 ? process.argv[i + 1] : "dev"; })();
loadDotEnvFile(path.join(__dirname, "..", ".env"));
loadDotEnvFile(path.join(__dirname, "..", ".env." + ENV_EARLY));

const N8N_URL = (process.env.N8N_URL || "").replace(/\/+$/, "");
const N8N_API_KEY = process.env.N8N_API_KEY || "";
const OFFLINE = !N8N_URL || !N8N_API_KEY;

// ---- config de entorno ----
const envCfgPath = path.join(ROOT, "envs", ENV + ".json");
if (!fs.existsSync(envCfgPath)) { console.error("No existe envs/" + ENV + ".json"); process.exit(1); }
const envCfg = JSON.parse(fs.readFileSync(envCfgPath, "utf8"));
const replacements = envCfg.replacements || {};
const credMap = envCfg.credentials || {};
const WF_DIR = path.join(ROOT, envCfg.folder || "workflows");

// ---- listar archivos de workflow (descarta basura) ----
function isJunk(f) { return /\.bak\.json$|premerge|whatsapp\.bak|\.disabled\./i.test(f); }
const exclude = new Set(envCfg.exclude || []);
let files = fs.readdirSync(WF_DIR).filter(f => f.endsWith(".json") && !isJunk(f));
files = files.filter(f => !exclude.has(f.replace(/\.json$/, "")));
if (ONLY) files = files.filter(f => f.replace(/\.json$/, "") === ONLY);

// ---- aplicar reemplazos de entorno sobre el JSON serializado ----
function applyReplacements(str) {
  let out = str;
  for (const [from, to] of Object.entries(replacements)) out = out.split(from).join(to);
  return out;
}

// ---- remapear credenciales por nombre (si el env lo define) ----
// credMap: { "<nombre en dev>": "<id destino>" }  o  { "<nombre dev>": {"id","name"} }.
// Setea el id (y el nombre destino si se da) en cada nodo cuya credencial coincide por nombre.
function remapCreds(wf) {
  if (!Object.keys(credMap).length) return;
  for (const n of wf.nodes || []) {
    if (!n.credentials) continue;
    for (const k of Object.keys(n.credentials)) {
      const c = n.credentials[k];
      if (!c || !c.name) continue;
      const target = credMap[c.name];
      if (target === undefined) continue;
      if (typeof target === "string") { c.id = target; }
      else { if (target.id) c.id = target.id; if (target.name) c.name = target.name; }
    }
  }
}

// ---- payload limpio para la API publica (solo campos permitidos) ----
// La API publica rechaza props extra en settings; se filtra a la whitelist del schema.
const SETTINGS_OK = ["saveExecutionProgress", "saveManualExecutions", "saveDataErrorExecution", "saveDataSuccessExecution", "executionTimeout", "errorWorkflow", "timezone", "executionOrder"];
function cleanSettings(s) {
  const out = {};
  if (s && typeof s === "object") for (const k of SETTINGS_OK) if (s[k] !== undefined) out[k] = s[k];
  return out;
}
function toPayload(wf) {
  return { name: wf.name, nodes: wf.nodes, connections: wf.connections, settings: cleanSettings(wf.settings) };
}

// ---- API helpers ----
async function api(method, p, body) {
  const res = await fetch(N8N_URL + "/api/v1" + p, {
    method,
    headers: { "X-N8N-API-KEY": N8N_API_KEY, "Content-Type": "application/json", accept: "application/json" },
    body: body ? JSON.stringify(body) : undefined
  });
  const text = await res.text();
  let json; try { json = text ? JSON.parse(text) : null; } catch { json = text; }
  if (!res.ok) throw new Error(method + " " + p + " -> " + res.status + " " + (typeof json === "string" ? json : JSON.stringify(json)));
  return json;
}

async function listAllWorkflows() {
  const byName = new Map();
  let cursor = null;
  do {
    const q = "?limit=250" + (cursor ? "&cursor=" + encodeURIComponent(cursor) : "");
    const r = await api("GET", "/workflows" + q);
    for (const w of (r.data || [])) {
      if (w.isArchived) continue; // ignora workflows archivados (no se pueden actualizar)
      byName.set(w.name, w.id);   // si hay duplicados activos, gana el ultimo
    }
    cursor = r.nextCursor || null;
  } while (cursor);
  return byName;
}

// ---- carga y normaliza todos los workflows de la carpeta ----
const workflows = files.map(f => {
  const raw = applyReplacements(fs.readFileSync(path.join(WF_DIR, f), "utf8"));
  const wf = JSON.parse(raw);
  remapCreds(wf);
  return { file: f, wf };
});

// ---- reescribe referencias entre workflows con el mapa nombre->id destino ----
function rewireRefs(wf, nameToId) {
  let changed = 0;
  for (const n of wf.nodes || []) {
    const isRef = n.type === "@n8n/n8n-nodes-langchain.toolWorkflow" || n.type === "n8n-nodes-base.executeWorkflow";
    if (!isRef) continue;
    const w = n.parameters && n.parameters.workflowId;
    if (!w || typeof w !== "object") continue;
    const targetName = w.cachedResultName;
    if (targetName && nameToId.has(targetName)) {
      const id = nameToId.get(targetName);
      if (w.value !== id) { w.value = id; changed++; }
    }
  }
  return changed;
}

(async () => {
  console.log("== n8n-sync ==  env=" + ENV + (DRY ? "  (DRY-RUN)" : "") + (OFFLINE ? "  (OFFLINE: sin N8N_URL/API_KEY)" : ""));
  console.log("carpeta: " + path.relative(ROOT, WF_DIR) + "  | workflows: " + workflows.length);
  console.log("reemplazos: " + (Object.keys(replacements).length ? Object.entries(replacements).map(([a, b]) => a + "->" + b).join(", ") : "(ninguno)"));

  if (OFFLINE) {
    console.log("\n-- Plan OFFLINE (no se conecta a n8n) --");
    for (const { file, wf } of workflows) console.log("  - " + wf.name + "  [" + file + "]");
    console.log("\nPara desplegar de verdad: defini N8N_URL y N8N_API_KEY (.env) y corre sin --dry-run.");
    return;
  }

  const existing = await listAllWorkflows();
  const nameToId = new Map(existing);

  // PASO 0: pre-enlazar referencias con el mapa de workflows YA existentes.
  // n8n no permite guardar un workflow que referencia subworkflows no publicados,
  // por eso hay que corregir las referencias ANTES del upsert (no despues).
  console.log("\n-- Paso 0: pre-enlazar referencias (existentes) --");
  for (const item of workflows) {
    const changed = rewireRefs(item.wf, nameToId);
    if (changed) console.log("  " + item.wf.name + ": " + changed + " ref(s)");
  }

  // PASO 1: upsert (crear/actualizar) y completar el mapa nombre->id del destino
  console.log("\n-- Paso 1: upsert --");
  for (const item of workflows) {
    const name = item.wf.name;
    const exists = existing.has(name);
    if (DRY) { console.log("  " + (exists ? "PUT " : "POST") + "  " + name); if (!exists) nameToId.set(name, "DRY-NEW-" + name); continue; }
    if (exists) {
      const id = existing.get(name);
      await api("PUT", "/workflows/" + id, toPayload(item.wf));
      nameToId.set(name, id);
      console.log("  PUT  " + name + "  (" + id + ")");
    } else {
      const created = await api("POST", "/workflows", toPayload(item.wf));
      nameToId.set(name, created.id);
      console.log("  POST " + name + "  (" + created.id + ")");
    }
  }

  // PASO 2: re-enlazar SOLO lo que apuntaba a workflows recien creados (ids nuevos)
  // y volver a guardar los que cambian.
  console.log("\n-- Paso 2: re-enlazar nuevos --");
  for (const item of workflows) {
    const changed = rewireRefs(item.wf, nameToId);
    if (!changed) continue;
    const id = nameToId.get(item.wf.name);
    if (DRY || String(id).startsWith("DRY-NEW-")) { console.log("  (dry) reenlazaria " + changed + " ref(s) en " + item.wf.name); continue; }
    await api("PUT", "/workflows/" + id, toPayload(item.wf));
    console.log("  reenlazadas " + changed + " ref(s) en " + item.wf.name);
  }

  // PASO 3 (opcional): activar
  if (ACTIVATE && !DRY) {
    console.log("\n-- Paso 3: activar --");
    for (const item of workflows) {
      if (envCfg.activate && !envCfg.activate.includes(item.wf.name)) continue;
      const id = nameToId.get(item.wf.name);
      try { await api("POST", "/workflows/" + id + "/activate"); console.log("  activado " + item.wf.name); }
      catch (e) { console.log("  no se pudo activar " + item.wf.name + ": " + e.message); }
    }
  }

  console.log("\nOK.");
})().catch(e => { console.error("\nERROR: " + e.message); process.exit(1); });
