const tablet = document.getElementById('tablet');
const closeBtn = document.getElementById('closeBtn');

const state = {
  dashboard: null,
};

function post(name, payload = {}) {
  return fetch(`https://${GetParentResourceName()}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(payload),
  }).catch(() => {});
}

function text(value, fallback = '-') {
  if (value === undefined || value === null || value === '') return fallback;
  return String(value);
}

function setText(id, value) {
  const el = document.getElementById(id);
  if (el) el.textContent = value;
}

function item(title, description, mode = '') {
  const node = document.createElement('div');
  node.className = `item ${mode}`;
  node.innerHTML = `<strong>${title}</strong><small>${description}</small>`;
  return node;
}

function metric(value) {
  const numeric = Number(value || 0);
  return Number.isFinite(numeric) ? numeric : 0;
}

function clearList(id) {
  const el = document.getElementById(id);
  if (el) el.replaceChildren();
  return el;
}

function asArray(value) {
  if (Array.isArray(value)) return value;
  if (value && typeof value === 'object') return Object.values(value);
  return [];
}

function operationPayload(data) {
  const payload = data.operations || {};
  return {
    operations: asArray(payload.operations || payload),
    active: payload.active || null,
  };
}

function renderStats(data) {
  const gang = data.gang || {};
  const criminal = (data.progress && data.progress.criminal) || {};
  const crafting = (data.progress && data.progress.crafting) || {};
  const airdrop = data.airdrop;

  setText('gangName', text(gang.label, 'Sin banda'));
  setText('gangTag', text(gang.tag || gang.name, 'NONE').toUpperCase());
  setText('gangRank', text(gang.rankLabel, 'Civil'));
  setText('criminalLevel', `N${text(criminal.level, 1)}`);
  setText('criminalRep', `Rep ${text(criminal.reputation, 0)}`);
  setText('craftLevel', `N${text(crafting.level, 1)}`);
  setText('craftRep', `Rep ${text(crafting.reputation, 0)}`);
  setText('airdropState', airdrop ? 'ACTIVO' : 'OFF');
  setText('airdropZone', airdrop ? text(airdrop.zoneLabel || airdrop.zoneId) : 'Sin senal');
}

function renderRisk(data) {
  const zones = data.territories || [];
  const markets = data.markets || [];
  const operationData = operationPayload(data);
  const operations = operationData.operations;
  const active = operationData.active;
  const zoneHeat = zones.reduce((highest, zone) => Math.max(highest, metric(zone.heatMultiplier) * 10), 0);
  const marketHeat = markets.reduce((total, market) => total + metric(market.heat), 0);
  const operationRisk = operations.reduce((highest, operation) => Math.max(highest, metric(operation.policeAlertChance)), 0);
  const score = Math.min(100, Math.round((zoneHeat * 0.35) + (marketHeat * 0.35) + (operationRisk * 0.3) + (active ? 12 : 0)));
  const label = score >= 70 ? 'critico' : (score >= 40 ? 'alto' : (score >= 20 ? 'medio' : 'bajo'));

  setText('riskScore', score);
  setText('riskLabel', label);
}

function renderTacticalMap(data) {
  const map = clearList('tacticalMap');
  const zones = [...(data.territories || [])].slice(0, 8);

  if (!zones.length) {
    map.appendChild(item('Sin senal', 'No hay zonas sincronizadas.'));
    return;
  }

  zones.forEach((zone) => {
    const node = document.createElement('div');
    const influence = Math.min(100, metric(zone.topInfluence));
    const status = text(zone.status, 'neutral');
    node.className = `zone ${status}`;
    node.innerHTML = `
      <div>
        <strong>${text(zone.label)}</strong>
        <small>${status} | ${text(zone.owner, 'none')}</small>
      </div>
      <span style="--value:${influence}%"></span>
    `;
    map.appendChild(node);
  });
}

function renderTerritories(data) {
  const list = clearList('territories');
  const zones = data.territories || [];
  if (!zones.length) {
    list.appendChild(item('Sin datos', 'Territorios no disponible.'));
    return;
  }

  zones.slice(0, 6).forEach((zone) => {
    const mode = zone.status === 'controlled' ? 'good' : (zone.status === 'contested' ? 'warn' : '');
    list.appendChild(item(
      text(zone.label),
      `${text(zone.status, 'neutral')} | Owner ${text(zone.owner, 'none')} | Influencia ${text(zone.topInfluence, 0)} | Heat x${text(zone.heatMultiplier, 1)}`,
      mode,
    ));
  });
}

function renderContracts(data) {
  const list = clearList('contracts');
  const contracts = data.contracts && data.contracts.contracts || [];
  const active = data.contracts && data.contracts.active;

  if (active) {
    list.appendChild(item('Contrato activo', `${text(active.id)} | ${text(active.stage)}`, 'warn'));
  }

  if (!contracts.length) {
    list.appendChild(item('Sin contratos', 'No hay contratos disponibles.'));
    return;
  }

  contracts.slice(0, 5).forEach((contract) => {
    const reward = contract.reward || {};
    const mode = contract.unlocked ? 'good' : '';
    const cd = Number(contract.cooldownRemaining || 0);
    list.appendChild(item(
      text(contract.label),
      `$${text(reward.cash, 0)} | XP ${text(reward.xp, 0)} | Rep ${text(reward.reputation, 0)} | Riesgo ${text(contract.policeAlertChance, 0)}%${cd > 0 ? ` | CD ${Math.ceil(cd / 60)}m` : ''}`,
      mode,
    ));
  });
}

function renderOperations(data) {
  const list = clearList('operations');
  const operationData = operationPayload(data);
  const operations = operationData.operations;
  const active = operationData.active;

  if (active) {
    list.appendChild(item('Operacion activa', `${text(active.id)} | ${text(active.stage)}`, 'warn'));
  }

  if (!operations.length) {
    list.appendChild(item('Sin operaciones', 'No hay operaciones de banda disponibles.'));
    return;
  }

  operations.slice(0, 5).forEach((operation) => {
    const reward = operation.rewards && operation.rewards.player || {};
    const cd = Number(operation.cooldownRemaining || 0);
    list.appendChild(item(
      text(operation.label),
      `${text(operation.type)} | $${text(reward.cash, 0)} | XP ${text(reward.xp, 0)} | Inf ${text(operation.influence, 0)} | Riesgo ${text(operation.policeAlertChance, 0)}%${cd > 0 ? ` | CD ${Math.ceil(cd / 60)}m` : ''}`,
      operation.unlocked ? 'good' : 'warn',
    ));
  });
}

function renderMarkets(data) {
  const list = clearList('markets');
  const markets = data.markets || [];
  if (!markets.length) {
    list.appendChild(item('Sin contactos', 'Mercado negro no disponible.'));
    return;
  }

  markets.forEach((market) => {
    const stock = (market.catalog || []).reduce((total, entry) => total + Number(entry.stock || 0), 0);
    list.appendChild(item(
      text(market.label),
      `Heat ${text(market.heat, 0)} | Stock ${stock} | Req rep ${text(market.minCriminalReputation, 0)}`,
      Number(market.heat || 0) > 40 ? 'hot' : (market.accessible ? 'good' : ''),
    ));
  });
}

function renderLabs(data) {
  const list = clearList('labs');
  const payload = data.labs || {};
  const labs = asArray(payload.labs || payload);
  if (!labs.length) {
    list.appendChild(item('Sin laboratorios', 'No hay laboratorios sincronizados.'));
    return;
  }

  labs.slice(0, 5).forEach((lab) => {
    const cd = Number(lab.cooldownRemaining || 0);
    const queue = Number(lab.queueRemaining || 0);
    const locked = !lab.unlocked || lab.active || cd > 0 || queue > 0;
    list.appendChild(item(
      text(lab.label),
      `N${text(lab.level, 1)} | Cond ${text(lab.condition, 100)}% | ${text(lab.zoneLabel || lab.zoneId)} | Riesgo ${text(lab.risk, 0)}% | Inf +${text(lab.influenceReward, 0)}${lab.active ? ' | ACTIVO' : ''}${queue > 0 ? ` | Cola ${Math.ceil(queue / 60)}m` : ''}${cd > 0 ? ` | CD ${Math.ceil(cd / 60)}m` : ''}`,
      locked ? 'warn' : 'good',
    ));
  });
}

function renderMembers(data) {
  const list = clearList('members');
  const payload = data.members || {};
  const members = asArray(payload.members || []);
  const permissions = payload.permissions || {};
  const permissionText = Object.keys(permissions).filter((key) => permissions[key]).join(', ');

  list.appendChild(item(
    payload.isBoss ? 'Liderazgo activo' : `Rango ${text(payload.rankLabel, payload.rank || 0)}`,
    permissionText || 'Sin permisos especiales',
    payload.isBoss ? 'good' : '',
  ));

  if (!members.length) {
    list.appendChild(item('Sin miembros', 'No hay miembros sincronizados.'));
    return;
  }

  members.slice(0, 6).forEach((member) => {
    list.appendChild(item(
      text(member.citizenid),
      `${text(member.rank_label, `Rango ${text(member.rank_level, 0)}`)} | Desde ${text(member.joined_at, 'n/a')}`,
      member.is_boss ? 'good' : '',
    ));
  });
}

function renderLaundering(data) {
  const list = clearList('laundering');
  const payload = data.laundering || {};
  const locations = asArray(payload.locations || payload);
  if (!locations.length) {
    list.appendChild(item('Sin contactos', 'No hay lavado sincronizado.'));
    return;
  }

  locations.slice(0, 5).forEach((location) => {
    const cd = Number(location.cooldownRemaining || 0);
    const locked = !location.unlocked || cd > 0;
    list.appendChild(item(
      text(location.label),
      `Com ${text(location.commissionPercent, 0)}% | Riesgo ${text(location.risk, 0)}% | Rep ${text(location.minCriminalReputation, 0)}${cd > 0 ? ` | CD ${Math.ceil(cd / 60)}m` : ''}`,
      locked ? 'warn' : 'good',
    ));
  });
}

function renderAudit(data) {
  const list = clearList('audit');
  const audit = data.audit || {};
  const rows = [];

  asArray(audit.gang).slice(0, 4).forEach((log) => {
    rows.push({
      title: text(log.action, 'gang'),
      description: `${text(log.actor_citizenid, 'system')} -> ${text(log.target_citizenid, '-')} | ${text(log.created_at, '')}`,
      mode: 'good',
    });
  });

  asArray(audit.labs).slice(0, 3).forEach((log) => {
    rows.push({
      title: `Lab ${text(log.lab_id)}`,
      description: `${text(log.status)} | Riesgo ${text(log.risk, 0)}% | XP ${text(log.xp, 0)} | Alerta ${metric(log.police_alert) > 0 ? 'SI' : 'NO'}`,
      mode: metric(log.police_alert) > 0 ? 'hot' : 'good',
    });
  });

  asArray(audit.laundering).slice(0, 3).forEach((log) => {
    rows.push({
      title: `Lavado ${text(log.location_id || log.locationId, '-')}`,
      description: `$${text(log.dirty_amount || log.dirtyAmount, 0)} -> $${text(log.clean_amount || log.cleanAmount, 0)} | Riesgo ${text(log.risk, 0)}%`,
      mode: metric(log.police_alert || log.policeAlert) > 0 ? 'hot' : 'warn',
    });
  });

  if (!rows.length) {
    list.appendChild(item('Sin auditoria', 'Aun no hay registros de banda/labs/lavado.'));
    return;
  }

  rows.slice(0, 8).forEach((row) => {
    list.appendChild(item(row.title, row.description, row.mode));
  });
}

function renderAssets(data) {
  const list = clearList('assets');
  const locations = data.assets && data.assets.locations || [];
  const vehicles = data.assets && data.assets.persistedVehicles || [];
  const out = vehicles.filter((vehicle) => vehicle.state === 'out').length;
  if (!locations.length) {
    list.appendChild(item('Sin safehouse', 'Tu banda no tiene assets configurados.'));
    return;
  }

  list.appendChild(item(
    'Garaje',
    `Registrados ${vehicles.length} | Fuera ${out}`,
    out > 0 ? 'warn' : 'good',
  ));

  locations.forEach((location) => {
    list.appendChild(item(
      text(location.label),
      `Stash ${location.canStash ? 'OK' : 'LOCK'} | Garaje ${location.canGarage ? 'OK' : 'LOCK'}`,
      'good',
    ));
  });
}

function renderLogs(data) {
  const list = clearList('operationLogs');
  const logs = data.operationLogs || [];
  if (!logs.length) {
    list.appendChild(item('Sin registros', 'Completa operaciones para alimentar la bitacora.'));
    return;
  }

  logs.slice(0, 8).forEach((log) => {
    list.appendChild(item(
      text(log.operation_id),
      `${text(log.status)} | $${text(log.reward_cash, 0)} | XP ${text(log.reward_xp, 0)} | Inf ${text(log.influence, 0)} | Alerta ${metric(log.police_alert) > 0 ? 'SI' : 'NO'}`,
      metric(log.police_alert) > 0 ? 'hot' : 'good',
    ));
  });
}

function render(data) {
  state.dashboard = data || {};
  renderStats(state.dashboard);
  renderRisk(state.dashboard);
  renderTacticalMap(state.dashboard);
  renderTerritories(state.dashboard);
  renderOperations(state.dashboard);
  renderMembers(state.dashboard);
  renderLabs(state.dashboard);
  renderLaundering(state.dashboard);
  renderContracts(state.dashboard);
  renderMarkets(state.dashboard);
  renderAssets(state.dashboard);
  renderLogs(state.dashboard);
  renderAudit(state.dashboard);
}

function close() {
  tablet.classList.add('hidden');
  post('close');
}

window.addEventListener('message', (event) => {
  const data = event.data || {};
  if (data.action === 'open') {
    tablet.classList.remove('hidden');
    render(data.dashboard || {});
  }

  if (data.action === 'update') {
    render(data.dashboard || {});
  }

  if (data.action === 'close') {
    tablet.classList.add('hidden');
  }
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape') close();
});

closeBtn.addEventListener('click', close);

document.querySelectorAll('[data-action]').forEach((button) => {
  button.addEventListener('click', () => {
    post('action', { action: button.dataset.action });
  });
});
