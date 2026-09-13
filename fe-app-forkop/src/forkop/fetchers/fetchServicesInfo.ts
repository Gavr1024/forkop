import { ForkopShellMethods } from '../methods';
import { logger } from '../services/logger.service';
import { store } from '../services/store.service';
import { refreshRuntimeUiState } from '../services/runtimeUiState.service';
import { Forkop } from '../types';

let latestServicesInfoRequestId = 0;

function getSettledMethodResponse<T>(
  scope: string,
  result: PromiseSettledResult<Forkop.MethodResponse<T>>,
): Forkop.MethodResponse<T> {
  if (result.status === 'fulfilled') {
    return result.value;
  }

  logger.error('[SERVICES_INFO]', `${scope} failed`, result.reason);

  return {
    success: false,
    error: result.reason instanceof Error ? result.reason.message : '',
  };
}

export async function fetchServicesInfo() {
  const requestId = ++latestServicesInfoRequestId;
  const uiState = await refreshRuntimeUiState({ force: true });

  if (requestId !== latestServicesInfoRequestId) {
    return;
  }

  if (uiState) {
    return uiState;
  }

  const [forkopResult, singboxResult, xrayResult] = await Promise.allSettled([
    ForkopShellMethods.getStatus(),
    ForkopShellMethods.getSingBoxStatus(),
    ForkopShellMethods.getXrayStatus(),
  ]);

  if (requestId !== latestServicesInfoRequestId) {
    return;
  }

  const forkop = getSettledMethodResponse('getStatus', forkopResult);
  const singbox = getSettledMethodResponse('getSingBoxStatus', singboxResult);
  const xray = getSettledMethodResponse('getXrayStatus', xrayResult);
  const previousData = store.get().servicesInfoWidget.data;

  store.set({
    servicesInfoWidget: {
      loading: false,
      failed: !forkop.success || !singbox.success,
      data: {
        singbox: singbox.success ? singbox.data.running : previousData.singbox,
        xray: xray.success
          ? xray.data.xray_process_running
          : previousData.xray,
        xrayInstalled: xray.success
          ? xray.data.xray_installed
          : previousData.xrayInstalled,
        forkopRunning: forkop.success
          ? forkop.data.running
          : previousData.forkopRunning,
        forkopEnabled: forkop.success
          ? forkop.data.enabled
          : previousData.forkopEnabled,
        forkopStatus: forkop.success
          ? forkop.data.status
          : previousData.forkopStatus,
      },
    },
  });

  return undefined;
}
