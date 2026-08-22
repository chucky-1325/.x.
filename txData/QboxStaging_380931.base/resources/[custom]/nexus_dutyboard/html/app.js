var shell = document.getElementById('dutyShell');
var body = document.getElementById('dutyBody');
var closeBtn = document.getElementById('dutyClose');

var currentStatus = null;
var confirmingExit = false;

function post(name, data) {
    var xhr = new XMLHttpRequest();
    xhr.open('POST', 'https://' + (window.GetParentResourceName ? GetParentResourceName() : 'nexus_dutyboard') + '/' + name);
    xhr.setRequestHeader('Content-Type', 'application/json; charset=UTF-8');
    xhr.send(JSON.stringify(data || {}));
}

function taskLabel(task, kind) {
    if (kind === 'lot') return 'Transporte activo (' + task.state + ')';
    return 'Fabricacion activa (' + task.state + ')';
}

function render() {
    if (!currentStatus) {
        body.innerHTML = '';
        return;
    }

    if (!currentStatus.eligible) {
        body.innerHTML = '<div class="duty-not-eligible">Este punto de fichaje es exclusivo del taller mecanico.</div>';
        return;
    }

    var hasIncident = currentStatus.craft && currentStatus.craft.incidentReason;
    var hasTasks = !!currentStatus.lot || !!currentStatus.craft;

    var pillClass = 'off';
    var pillText = 'Fuera de servicio';
    if (currentStatus.onDuty) {
        pillClass = hasIncident ? 'busy' : 'on';
        pillText = hasIncident ? 'En servicio - incidencia' : (hasTasks ? 'En servicio - con tareas' : 'En servicio');
    }

    var html = '';
    html += '<span class="duty-pill ' + pillClass + '">' + pillText + '</span>';

    if (currentStatus.grade) {
        html += '<div class="duty-grade">Rango: ' + currentStatus.grade.name + ' (nivel ' + currentStatus.grade.level + ')</div>';
    }

    if (hasIncident) {
        html += '<div class="duty-incident">';
        html += '<div class="t">Incidencia pendiente</div>';
        html += '<div class="d">Hay una reserva de fabricacion retenida para revision administrativa. Motivo: ' + currentStatus.craft.incidentReason + '</div>';
        html += '</div>';
    }

    if (hasTasks) {
        html += '<div class="duty-section-title">Tareas activas</div>';
        html += '<div class="duty-tasks">';
        if (currentStatus.lot) {
            html += '<div class="duty-task">' + taskLabel(currentStatus.lot, 'lot') + '</div>';
        }
        if (currentStatus.craft) {
            html += '<div class="duty-task">' + taskLabel(currentStatus.craft, 'craft') + '</div>';
        }
        html += '</div>';
    }

    if (confirmingExit) {
        html += '<div class="duty-confirm">';
        html += '<p>Tienes tareas activas. ¿Fichar salida de todos modos? Las tareas seguiran abiertas.</p>';
        html += '<div class="duty-confirm-actions">';
        html += '<button type="button" class="duty-confirm-cancel" id="dutyConfirmCancel">Cancelar</button>';
        html += '<button type="button" class="duty-confirm-ok" id="dutyConfirmOk">Confirmar salida</button>';
        html += '</div></div>';
    } else {
        html += '<div class="duty-actions">';
        html += '<button type="button" class="duty-btn ' + (currentStatus.onDuty ? 'off' : '') + '" id="dutyToggle">';
        html += currentStatus.onDuty ? 'Fichar salida' : 'Fichar entrada';
        html += '</button></div>';
    }

    body.innerHTML = html;

    if (confirmingExit) {
        document.getElementById('dutyConfirmCancel').addEventListener('click', function () {
            confirmingExit = false;
            render();
        });
        document.getElementById('dutyConfirmOk').addEventListener('click', function () {
            confirmingExit = false;
            doToggle();
        });
        return;
    }

    var toggleBtn = document.getElementById('dutyToggle');
    if (toggleBtn) {
        toggleBtn.addEventListener('click', function () {
            var hasTasksNow = !!(currentStatus.lot || currentStatus.craft);
            if (currentStatus.onDuty && hasTasksNow) {
                confirmingExit = true;
                render();
                return;
            }
            doToggle();
        });
    }
}

function doToggle() {
    var xhr = new XMLHttpRequest();
    xhr.open('POST', 'https://' + (window.GetParentResourceName ? GetParentResourceName() : 'nexus_dutyboard') + '/toggle');
    xhr.setRequestHeader('Content-Type', 'application/json; charset=UTF-8');
    xhr.onload = function () {
        try {
            var res = JSON.parse(xhr.responseText);
            if (res && res.ok && currentStatus) {
                currentStatus.onDuty = !!res.onDuty;
                render();
            }
        } catch (e) { /* ignore malformed response */ }
    };
    xhr.send(JSON.stringify({}));
}

function closePanel() {
    shell.classList.remove('active');
    confirmingExit = false;
    currentStatus = null;
    post('close', {});
}

closeBtn.addEventListener('click', closePanel);

document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && shell.classList.contains('active')) {
        closePanel();
    }
});

window.addEventListener('message', function (event) {
    var data = event.data;
    if (!data || !data.action) return;

    if (data.action === 'open') {
        currentStatus = data.status;
        confirmingExit = false;
        render();
        shell.classList.add('active');
    } else if (data.action === 'close') {
        shell.classList.remove('active');
        confirmingExit = false;
        currentStatus = null;
    }
});
