import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  checkXray: vi.fn(),
  updateCheckStore: vi.fn(),
}));

vi.mock('../../../../methods', () => ({
  ForkopShellMethods: {
    checkXray: mocks.checkXray,
  },
}));

vi.mock('../updateCheckStore', () => ({
  updateCheckStore: mocks.updateCheckStore,
}));

import { runXrayCheck } from '../runXrayCheck';

const unusedXray = {
  xray_installed: 0,
  xray_version_ok: 0,
  xray_service_exist: 0,
  xray_autostart_disabled: 1,
  xray_process_running: 0,
  xray_ports_listening: 1,
  xray_sections_configured: 0,
};

describe('runXrayCheck', () => {
  beforeEach(() => {
    mocks.checkXray.mockReset();
    mocks.updateCheckStore.mockReset();
  });

  it('does not report listening ports when Xray is not installed', async () => {
    mocks.checkXray.mockResolvedValue({
      success: true,
      data: unusedXray,
    });

    await expect(runXrayCheck()).resolves.toBeUndefined();

    const result = mocks.updateCheckStore.mock.calls.slice(-1)[0]?.[0];
    expect(result.items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          state: 'warning',
          key: 'Xray is not installed',
        }),
        expect.objectContaining({
          state: 'warning',
          key: 'Xray is not listening on ports',
        }),
        expect.objectContaining({
          state: 'warning',
          key: 'Xray version is unknown',
        }),
      ]),
    );
    expect(result.items).not.toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          state: 'success',
          key: 'Xray listening ports',
        }),
      ]),
    );
  });
});
