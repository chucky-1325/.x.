function NexusCraftingEnsureTables()
    -- Phase 1B never mutates schema at runtime. Legacy tables are optional here.
    return false
end

function NexusCraftingLog(citizenid, stationId, recipeId, output)
    MySQL.insert.await([[
        INSERT INTO nexus_crafting_logs (citizenid, station_id, recipe_id, output_item, output_count)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        citizenid,
        stationId,
        recipeId,
        output.item,
        output.count or 1,
    })
end

function NexusCraftingLogSensitive(data)
    MySQL.insert.await([[
        INSERT INTO nexus_crafting_sensitive_logs
            (citizenid, source_id, station_id, recipe_id, output_item, output_count, blueprint_item, police_alert, risk_chance, x, y, z)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        data.citizenid,
        data.source,
        data.stationId,
        data.recipeId,
        data.output and data.output.item,
        data.output and (data.output.count or 1) or 1,
        data.blueprint,
        data.policeAlert and 1 or 0,
        data.riskChance or 0,
        data.coords and data.coords.x,
        data.coords and data.coords.y,
        data.coords and data.coords.z,
    })
end

function NexusCraftingFetchWorkbenches()
    return MySQL.query.await('SELECT * FROM nexus_crafting_workbenches') or {}
end

function NexusCraftingSaveWorkbench(bench)
    MySQL.update.await([[
        INSERT INTO nexus_crafting_workbenches
            (id, label, type, category, enabled, job, jobs, model, recipes, x, y, z, heading, sx, sy, sz, created_by)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
            label = VALUES(label),
            type = VALUES(type),
            category = VALUES(category),
            enabled = VALUES(enabled),
            job = VALUES(job),
            jobs = VALUES(jobs),
            model = VALUES(model),
            recipes = VALUES(recipes),
            x = VALUES(x),
            y = VALUES(y),
            z = VALUES(z),
            heading = VALUES(heading),
            sx = VALUES(sx),
            sy = VALUES(sy),
            sz = VALUES(sz)
    ]], {
        bench.id,
        bench.label,
        bench.type,
        bench.category,
        bench.enabled == false and 0 or 1,
        bench.job,
        json.encode(bench.jobs or {}),
        bench.model,
        json.encode(bench.recipes or {}),
        bench.coords.x,
        bench.coords.y,
        bench.coords.z,
        bench.heading or 0.0,
        bench.size.x,
        bench.size.y,
        bench.size.z,
        bench.createdBy,
    })
end

function NexusCraftingDeleteWorkbench(benchId)
    return MySQL.update.await('DELETE FROM nexus_crafting_workbenches WHERE id = ?', { benchId })
end
