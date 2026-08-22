const tablet = document.getElementById('tablet');
const actions = document.getElementById('actions');
const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'nexus_ems';

const text = (id, value) => {
    document.getElementById(id).textContent = value;
};

const post = async (endpoint, payload = {}) => {
    try {
        const response = await fetch(`https://${resource}/${endpoint}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload),
        });
        return await response.json();
    } catch (_) {
        return { success: false };
    }
};

const triageFor = (vitals) => {
    if (vitals.dead || vitals.health <= 115) return ['critical', 'CRITICO'];
    if (vitals.health <= 160 || vitals.bleeding >= 2) return ['warning', 'URGENTE'];
    return ['stable', 'ESTABLE'];
};

const renderActions = (items) => {
    actions.replaceChildren();
    (items || []).forEach((action) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'treatment';
        button.disabled = !action.available;

        const title = document.createElement('strong');
        title.textContent = action.label;
        const description = document.createElement('span');
        description.textContent = action.description;
        button.append(title, description);

        if (action.item) {
            const item = document.createElement('small');
            item.textContent = `Material: ${action.item}`;
            button.append(item);
        }

        button.addEventListener('click', () => post('treat', { actionId: action.id }));
        actions.append(button);
    });
};

const render = (payload) => {
    const patient = payload.patient || {};
    const vitals = payload.vitals || {};
    text('patient-name', patient.name || 'Sin identificar');
    text('patient-id', `ID ${patient.serverId ?? '--'}`);
    text('pulse', vitals.pulse ?? '--');
    text('respiration', vitals.respiration ?? '--');
    text('health', vitals.health ?? '--');
    text('status-chip', String(vitals.consciousness || 'sin evaluar').toUpperCase());
    text('bleeding-text', `${vitals.bleeding || 0} / 4`);
    text('pain-text', `${vitals.pain || 0} / 4`);
    document.getElementById('bleeding-bar').style.width = `${Math.min(100, (vitals.bleeding || 0) * 25)}%`;
    document.getElementById('pain-bar').style.width = `${Math.min(100, (vitals.pain || 0) * 25)}%`;

    const [triageClass, triageLabel] = triageFor(vitals);
    const triage = document.getElementById('triage');
    triage.className = `triage ${triageClass}`;
    text('triage-label', triageLabel);

    const stable = document.getElementById('flag-stable');
    stable.textContent = vitals.stabilized ? 'ESTABILIZADO' : 'NO ESTABILIZADO';
    stable.classList.toggle('active', Boolean(vitals.stabilized));
    const transport = document.getElementById('flag-transport');
    transport.textContent = vitals.transportReady ? 'LISTO PARA TRASLADO' : 'TRASLADO PENDIENTE';
    transport.classList.toggle('active', Boolean(vitals.transportReady));
    renderActions(payload.actions);
};

window.addEventListener('message', (event) => {
    const data = event.data || {};
    if (data.action === 'open') {
        render(data.payload || {});
        tablet.classList.add('visible');
        tablet.setAttribute('aria-hidden', 'false');
    } else if (data.action === 'close') {
        tablet.classList.remove('visible');
        tablet.setAttribute('aria-hidden', 'true');
    }
});

document.getElementById('close').addEventListener('click', () => post('close'));
document.getElementById('hospital').addEventListener('click', () => post('setWaypoint'));
window.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') post('close');
});

setInterval(() => {
    const now = new Date();
    text('clock', now.toLocaleTimeString('es-ES', { hour: '2-digit', minute: '2-digit' }));
}, 1000);

