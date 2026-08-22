(function () {
    'use strict';

    var app = document.getElementById('app');
    var stationName = document.getElementById('stationName');
    var category = document.getElementById('category');
    var level = document.getElementById('level');
    var xpLabel = document.getElementById('xpLabel');
    var repLabel = document.getElementById('repLabel');
    var xpBar = document.getElementById('xpBar');
    var recipes = document.getElementById('recipes');
    var selected = document.getElementById('selected');
    var blueprintIcon = document.getElementById('blueprintIcon');
    var blueprintItem = document.getElementById('blueprintItem');
    var craftOverlay = document.getElementById('craftOverlay');
    var craftProgressTitle = document.getElementById('craftProgressTitle');
    var craftProgressText = document.getElementById('craftProgressText');
    var craftProgressBar = document.getElementById('craftProgressBar');
    var closeButton = document.getElementById('close');
    var refreshButton = document.getElementById('refresh');

    var resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nexus_crafting';
    var currentStation = null;
    var selectedEntry = null;
    var selectedQty = 1;
    var readySent = false;
    var craftingActive = false;
    var progressTimer = null;
    window.__nexusCraftingAppLoaded = true;

    function post(name, data) {
        try {
            var request = new XMLHttpRequest();
            request.open('POST', 'https://' + resource + '/' + name, true);
            request.setRequestHeader('Content-Type', 'application/json; charset=UTF-8');
            request.send(JSON.stringify(data || {}));
        } catch (error) {
            return null;
        }

        return null;
    }

    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    function asList(value) {
        var keys;
        var list = [];
        var i;

        if (Object.prototype.toString.call(value) === '[object Array]') return value;
        if (!value || typeof value !== 'object') return [];

        keys = Object.keys(value).sort(function (a, b) {
            return Number(a) - Number(b);
        });

        for (i = 0; i < keys.length; i += 1) {
            list.push(value[keys[i]]);
        }

        return list;
    }

    function iconFor(recipe) {
        var item = recipe && recipe.output && recipe.output.item ? recipe.output.item : 'N';
        return String(item).slice(0, 1).toUpperCase();
    }

    function itemImage(item) {
        return 'nui://ox_inventory/web/images/' + encodeURIComponent(item || 'unknown') + '.png';
    }

    function itemIcon(item, fallback, extraClass) {
        var safeItem = escapeHtml(item || '');
        var safeFallback = escapeHtml(fallback || String(item || 'N').slice(0, 1).toUpperCase());

        return '<span class="item-icon ' + escapeHtml(extraClass || '') + '">' +
            '<img src="' + itemImage(item) + '" alt="' + safeItem + '" onerror="this.style.display=&quot;none&quot;;this.nextSibling.style.display=&quot;flex&quot;">' +
            '<b>' + safeFallback + '</b>' +
        '</span>';
    }

    function missingMap(entry) {
        var map = {};
        var missing = asList(entry && entry.missing);
        var i;

        for (i = 0; i < missing.length; i += 1) {
            if (missing[i] && missing[i].item) map[missing[i].item] = missing[i];
        }

        return map;
    }

    function ingredientPill(ingredient, missing, held) {
        var text;

        if (!ingredient) return '';
        text = ingredient.count + 'x ' + ingredient.item;
        if (!held && missing) text = ingredient.item + ' ' + missing.current + '/' + missing.required;

        return '<span class="pill ' + (held ? 'held' : (missing ? 'missing' : '')) + '">' + itemIcon(ingredient.item, null, 'mini') + '<span>' + escapeHtml(text) + '</span></span>';
    }

    function recipeBadges(entry, recipe) {
        var html = '';

        if (entry && entry.hidden) html += '<span class="badge classified">Clasificado</span>';
        if (recipe && recipe.blueprint) html += '<span class="badge blueprint-badge">Blueprint</span>';
        if (entry && entry.hasBlueprint === false) html += '<span class="badge missing-blueprint">Plano requerido</span>';
        if ((entry && entry.sensitive) || (recipe && recipe.sensitive)) html += '<span class="badge sensitive">Sensible</span>';
        if ((entry && entry.risk) || (recipe && recipe.risk)) html += '<span class="badge risk">Riesgo</span>';

        return html;
    }

    function selectRecipe(entry) {
        selectedEntry = entry;
        selectedQty = 1;
        renderRecipes(currentStation);
        renderSelected(entry);
    }

    function renderRecipes(station) {
        var list = asList(station && station.recipes);
        var i;

        recipes.innerHTML = '';

        for (i = 0; i < list.length; i += 1) {
            (function (entry) {
                var recipe = entry && entry.data ? entry.data : {};
                var locked = !entry.unlocked;
                var row = document.createElement('button');
                var isActive = selectedEntry && selectedEntry.id === entry.id;

                row.className = 'recipe-row ' + (isActive ? 'active ' : '') + (locked ? 'locked ' : '') + (entry.hidden ? 'classified-row ' : '') + (entry.hasBlueprint === false ? 'needs-blueprint ' : '');
                row.type = 'button';
                row.innerHTML =
                    itemIcon(recipe.output && recipe.output.item, iconFor(recipe), 'recipe-icon') +
                    '<span class="recipe-name">' +
                        '<strong>' + escapeHtml(recipe.label || entry.id || 'Receta') + '</strong>' +
                        '<span>' + escapeHtml(entry.hidden ? 'Informacion restringida' : ((recipe.output && recipe.output.count ? recipe.output.count : 1) + 'x ' + (recipe.output && recipe.output.item ? recipe.output.item : 'item'))) + '</span>' +
                        '<em class="recipe-badges">' + recipeBadges(entry, recipe) + '</em>' +
                    '</span>' +
                    '<span class="recipe-level">' + escapeHtml(entry.hidden ? '???' : (recipe.requiredLevel || 1)) + ' lvl</span>';
                row.addEventListener('click', function () {
                    selectRecipe(entry);
                });
                recipes.appendChild(row);
            }(list[i]));
        }
    }

    function renderSelected(entry) {
        var recipe;
        var missingByItem;
        var locked;
        var missingList;
        var hasMissing;
        var disabled;
        var ingredients;
        var ingredientHtml = '';
        var i;
        var quarantined;

        if (!entry) {
            selected.innerHTML = '<p>Selecciona una receta.</p>';
            blueprintIcon.textContent = 'N';
            blueprintItem.textContent = 'Selecciona una receta';
            return;
        }

        recipe = entry.data || {};
        if (entry.hidden) {
            blueprintIcon.textContent = '?';
            blueprintItem.textContent = 'Receta clasificada';
            selected.innerHTML =
                '<h2>Clasificado</h2>' +
                '<p>Esta receta requiere mas progreso antes de revelar sus materiales y resultado.</p>' +
                '<div class="pills">' +
                    '<span class="pill">Nivel requerido ' + escapeHtml(recipe.hiddenUntilLevel || recipe.requiredLevel || '?') + '</span>' +
                    '<span class="pill">Reputacion requerida ' + escapeHtml(recipe.hiddenUntilReputation || 0) + '</span>' +
                    recipeBadges(entry, recipe) +
                '</div>';
            return;
        }

        quarantined = !!(currentStation && currentStation.quarantine);

        missingByItem = missingMap(entry);
        locked = !entry.unlocked;
        missingList = asList(entry.missing);
        hasMissing = missingList.length > 0;
        disabled = locked || hasMissing || craftingActive || quarantined;
        ingredients = asList(recipe.ingredients);

        for (i = 0; i < ingredients.length; i += 1) {
            ingredientHtml += quarantined
                ? ingredientPill(ingredients[i], null, true)
                : ingredientPill(ingredients[i], missingByItem[ingredients[i].item]);
        }

        blueprintIcon.innerHTML = itemIcon(recipe.output && recipe.output.item, iconFor(recipe), 'blueprint-art');
        blueprintItem.textContent = (recipe.output && recipe.output.count ? recipe.output.count : 1) + 'x ' + (recipe.output && recipe.output.item ? recipe.output.item : 'item');
        selected.innerHTML =
            '<h2>' + escapeHtml(recipe.label || entry.id || 'Receta') + '</h2>' +
            '<p>' + escapeHtml(recipe.category || 'crafting') + ' | ' + Math.ceil(Number(recipe.duration || 5000) / 1000) + 's | +' + escapeHtml(recipe.xp || 0) + ' XP</p>' +
            (quarantined
                ? '<div class="craft-quarantine">' +
                    '<div class="t">⚠ Incidencia pendiente</div>' +
                    '<div class="d">Hay una incidencia pendiente en este banco. Los materiales están retenidos para revisión administrativa.</div>' +
                  '</div>' +
                  '<div class="craft-btn-disabled">Fabricar — bloqueado</div>'
                : '<div class="craft-controls">' +
                    '<div class="qty">' +
                        '<button id="minus" type="button">-</button>' +
                        '<span>' + selectedQty + '</span>' +
                        '<button id="plus" type="button">+</button>' +
                    '</div>' +
                    '<button id="craftSelected" class="craft" type="button" ' + (disabled ? 'disabled' : '') + '>' +
                        escapeHtml(craftingActive ? 'Fabricando...' : (locked ? entry.lockedReason : (hasMissing ? 'Sin materiales' : 'Fabricar'))) +
                    '</button>' +
                  '</div>') +
            '<div class="section-title">REQUISITOS</div>' +
            '<div class="pills">' +
                '<span class="pill">Nivel ' + escapeHtml(recipe.requiredLevel || 1) + '</span>' +
                '<span class="pill">Rep ' + escapeHtml(entry.requiredReputation || recipe.hiddenUntilReputation || 0) + '</span>' +
                (recipe.blueprint ? '<span class="pill ' + (entry.hasBlueprint === false ? 'missing' : '') + '">' + itemIcon(recipe.blueprint, null, 'mini') + '<span>' + escapeHtml(recipe.blueprint) + '</span></span>' : '') +
                recipeBadges(entry, recipe) +
            '</div>' +
            '<div class="section-title">INGREDIENTES</div>' +
            '<div class="pills">' + ingredientHtml + '</div>' +
            '<div class="section-title">RESULTADO</div>' +
            '<div class="pills">' +
                '<span class="pill">' + escapeHtml((recipe.output && recipe.output.count ? recipe.output.count : 1) + 'x ' + (recipe.output && recipe.output.item ? recipe.output.item : 'item')) + '</span>' +
            '</div>';

        if (quarantined) return;

        document.getElementById('minus').addEventListener('click', function () {
            selectedQty = Math.max(1, selectedQty - 1);
            renderSelected(entry);
        });

        document.getElementById('plus').addEventListener('click', function () {
            selectedQty = Math.min(10, selectedQty + 1);
            renderSelected(entry);
        });

        document.getElementById('craftSelected').addEventListener('click', function () {
            if (craftingActive) return;
            craftingActive = true;
            document.getElementById('craftSelected').textContent = 'Validando...';
            document.getElementById('craftSelected').disabled = true;
            post('craft', { recipeId: entry.id, count: selectedQty });
        });
    }

    function openCrafting(station) {
        var stationRecipes;
        var progress;
        var current;
        var required;
        var percent;

        currentStation = station || {};
        craftingActive = false;
        stationRecipes = asList(currentStation.recipes);
        selectedEntry = stationRecipes[0] || null;
        progress = currentStation.progress || {};
        current = Number(progress.currentXp || 0);
        required = Math.max(Number(progress.requiredXp || 1000), 1);
        percent = Math.min(100, Math.max(0, (current / required) * 100));

        stationName.textContent = currentStation.label || 'Mesa de crafting';
        category.textContent = currentStation.categoryLabel || currentStation.category || 'Crafting';
        level.textContent = 'Nivel ' + (progress.level || 1);
        xpLabel.textContent = current + ' / ' + required + ' XP';
        repLabel.textContent = 'Rep ' + (progress.reputation || 0);
        xpBar.style.width = percent + '%';
        app.classList.add('active');
        app.setAttribute('aria-hidden', 'false');
        post('opened', {});

        renderRecipes(currentStation);
        renderSelected(selectedEntry);
    }

    function closeCrafting() {
        app.classList.remove('active');
        app.setAttribute('aria-hidden', 'true');
    }

    function hideCraftProgress(delay) {
        window.setTimeout(function () {
            if (progressTimer) {
                window.clearInterval(progressTimer);
                progressTimer = null;
            }

            craftOverlay.classList.remove('active', 'complete', 'cancelled');
            craftOverlay.setAttribute('aria-hidden', 'true');
            craftProgressBar.style.width = '0%';
            craftingActive = false;
            if (selectedEntry) renderSelected(selectedEntry);
        }, delay || 0);
    }

    function startCraftProgress(data) {
        var duration = Math.max(Number(data && data.duration || 5000), 500);
        var started = Date.now();

        if (progressTimer) window.clearInterval(progressTimer);
        craftingActive = true;
        craftOverlay.classList.remove('complete', 'cancelled');
        craftOverlay.classList.add('active');
        craftOverlay.setAttribute('aria-hidden', 'false');
        craftProgressTitle.textContent = 'Fabricando';
        craftProgressText.textContent = data && data.label ? data.label : 'Procesando receta';
        craftProgressBar.style.width = '0%';
        if (selectedEntry) renderSelected(selectedEntry);

        progressTimer = window.setInterval(function () {
            var percent = Math.min(98, ((Date.now() - started) / duration) * 100);
            craftProgressBar.style.width = percent + '%';
        }, 80);
    }

    function finishCraftProgress(data) {
        if (progressTimer) {
            window.clearInterval(progressTimer);
            progressTimer = null;
        }

        craftProgressBar.style.width = '100%';
        craftOverlay.classList.add(data && data.cancelled ? 'cancelled' : 'complete');
        craftProgressTitle.textContent = data && data.cancelled ? 'Cancelado' : 'Completado';
        craftProgressText.textContent = data && data.message ? data.message : (data && data.cancelled ? 'Fabricacion cancelada.' : 'Objeto fabricado.');
        hideCraftProgress(900);
    }

    function openDiagnostic(data) {
        stationName.textContent = data && data.label ? data.label : 'NUI TEST';
        category.textContent = 'Diagnostico';
        level.textContent = 'OK';
        xpLabel.textContent = 'NUI activa';
        repLabel.textContent = 'Test';
        xpBar.style.width = '100%';
        recipes.innerHTML = '<button class="recipe-row active" type="button"><span class="recipe-icon">N</span><span class="recipe-name"><strong>Diagnostico</strong><span>HTML cargado</span></span><span class="recipe-level">OK</span></button>';
        selected.innerHTML = '<h2>NUI cargada</h2><p>' + escapeHtml(data && data.message ? data.message : 'La interfaz responde.') + '</p>';
        blueprintIcon.textContent = 'OK';
        blueprintItem.textContent = 'Diagnostico';
        app.classList.add('active');
        app.setAttribute('aria-hidden', 'false');
        post('opened', {});
    }

    function bootReady() {
        if (readySent) return;
        readySent = true;
        post('ready', { source: 'app' });
    }

    window.addEventListener('message', function (event) {
        var payload = event && event.data ? event.data : {};

        if (payload.action === 'open') {
            try {
                openCrafting(payload.data || {});
            } catch (error) {
                app.classList.add('active');
                app.setAttribute('aria-hidden', 'false');
                selected.innerHTML = '<p>Error cargando interfaz. Revisa F8.</p>';
                post('opened', {});
                post('uiError', { message: error && error.message ? error.message : String(error) });
            }
        }

        if (payload.action === 'diagnostic') openDiagnostic(payload.data || {});
        if (payload.action === 'craftProgress') {
            if (payload.data && payload.data.state === 'start') startCraftProgress(payload.data);
            if (payload.data && (payload.data.state === 'complete' || payload.data.state === 'cancelled')) finishCraftProgress(payload.data);
        }
        if (payload.action === 'close') closeCrafting();
    });

    if (closeButton) {
        closeButton.addEventListener('click', function () {
            post('close', {});
        });
    }

    if (refreshButton) {
        refreshButton.addEventListener('click', function () {
            post('refresh', {});
        });
    }

    window.addEventListener('keydown', function (event) {
        if (event.key === 'Escape' || event.keyCode === 27) post('close', {});
    });

    document.addEventListener('DOMContentLoaded', bootReady);
    window.addEventListener('load', bootReady);
    bootReady();
}());
