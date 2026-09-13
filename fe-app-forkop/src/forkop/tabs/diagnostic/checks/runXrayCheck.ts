import { DIAGNOSTICS_CHECKS_MAP } from './contstants';
import { ForkopShellMethods } from '../../../methods';
import { updateCheckStore } from './updateCheckStore';
import { getMeta } from '../helpers/getMeta';

export async function runXrayCheck() {
  const { order, title, code } = DIAGNOSTICS_CHECKS_MAP.XRAY;

  updateCheckStore({
    order,
    code,
    title,
    description: _('Checking, please wait'),
    state: 'loading',
    items: [],
  });

  const xrayChecks = await ForkopShellMethods.checkXray();

  if (!xrayChecks.success) {
    updateCheckStore({
      order,
      code,
      title,
      description: _('Cannot receive checks result'),
      state: 'error',
      items: [],
    });

    throw new Error('Xray checks failed');
  }

  const data = xrayChecks.data;
  const installed = Boolean(data.xray_installed);
  const configured = Boolean(data.xray_sections_configured);
  const portsListening = installed && Boolean(data.xray_ports_listening);

  const allGood = configured
    ? installed &&
      Boolean(data.xray_version_ok) &&
      Boolean(data.xray_service_exist) &&
      Boolean(data.xray_autostart_disabled) &&
      Boolean(data.xray_process_running) &&
      portsListening
    : installed && Boolean(data.xray_version_ok);

  const atLeastOneGood =
    installed ||
    Boolean(data.xray_version_ok) ||
    Boolean(data.xray_service_exist) ||
    Boolean(data.xray_autostart_disabled) ||
    Boolean(data.xray_process_running) ||
    portsListening ||
    configured;

  const { state, description } = getMeta({ atLeastOneGood, allGood });

  updateCheckStore({
    order,
    code,
    title,
    description,
    state,
    items: [
      {
        state: data.xray_installed ? 'success' : configured ? 'error' : 'warning',
        key: data.xray_installed ? _('Xray installed') : _('Xray is not installed'),
        value: '',
      },
      {
        state: data.xray_version_ok ? 'success' : data.xray_installed ? 'error' : 'warning',
        key: data.xray_version_ok
          ? _('Xray version is compatible (newer than 24.12.0)')
          : data.xray_installed
            ? _('Xray version is incompatible')
            : _('Xray version is unknown'),
        value: '',
      },
      {
        state: data.xray_service_exist ? 'success' : configured ? 'error' : 'warning',
        key: _('Xray service exist'),
        value: '',
      },
      {
        state: data.xray_autostart_disabled ? 'success' : 'warning',
        key: _('Xray autostart disabled'),
        value: '',
      },
      {
        state: data.xray_process_running
          ? 'success'
          : configured
            ? 'error'
            : 'warning',
        key: data.xray_process_running
          ? _('Xray process running')
          : _('Xray process is not running'),
        value: '',
      },
      {
        state: portsListening
          ? 'success'
          : configured
            ? 'error'
            : 'warning',
        key: portsListening
          ? _('Xray listening ports')
          : _('Xray is not listening on ports'),
        value: '',
      },
      {
        state: configured ? 'success' : 'warning',
        key: configured
          ? _('Xray sections are configured')
          : _('No Xray sections are configured'),
        value: '',
      },
    ],
  });

  if (configured && (!data.xray_installed || !data.xray_process_running)) {
    throw new Error('Xray checks failed');
  }
}
