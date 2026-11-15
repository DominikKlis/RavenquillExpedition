-- Ratchet baseline for scripts/check-architecture.lua. Values only ever tighten (--update).
-- allow: globals the suite may write; legacy: allowed for now, counted by legacy_globals until removed.
return {
  metrics = {
    cached_trace = 0,
    checks_passed = 1777,
    checks_skipped = 0,
    core_internals = 0,
    dev_abs_paths = 0,
    dup_primitives = 0,
    foreign_addon_refs = 0,
    foreign_prefixes = 0,
    global_writes = 0,
    goal_module_lines = 25,
    legacy_globals = 0,
    luacheck_warnings = 0,
    main_slots = 78,
    max_file_lines = 919,
    no_core_dep = 0,
    own_mechanisms = 0,
    plan_refs = 0,
    send_hooks = 1,
    send_sites = 0,
    swallowed_errors = 0,
    version_literals = 0,
  },
  allow = { "RavenquillExpedition", "RavenquillExpeditionDB", "SLASH_RAVENQUILL1", "SLASH_RAVENQUILL2", "RavenquillExpedition_OnCompartmentClick", "RavenquillExpeditionCraftDB", "RavenquillExpedition_CraftAdvisor_OnCompartmentClick", "RavenquillExpeditionHighlightsDB", "RavenquillExpeditionHighlightsCharDB", "RavenquillExpeditionMap", "RavenquillExpeditionMapDB", "RavenquillExpeditionDevDB", "RQDevInbox" },
  legacy = {  },
}
