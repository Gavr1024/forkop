import type { StoreType } from '../services/store.service';
import type { Forkop } from '../types';

export type UpdatesActionKey = keyof StoreType['updatesActions'];

const componentActionKeyMap: Record<string, UpdatesActionKey> = {
  'forkop:check_update': 'forkopCheck',
  'forkop:install': 'forkopInstall',
  'sing_box:check_update': 'singBoxCheck',
  'sing_box:install': 'singBoxInstall',
  'sing_box:install_extended': 'singBoxInstallExtended',
  'sing_box:install_extended_compressed': 'singBoxInstallExtendedCompressed',
  'sing_box:install_tiny': 'singBoxInstallTiny',
  'sing_box:install_stable': 'singBoxInstallStable',
  'sing_box:list_versions': 'singBoxCheck',
  'zapret:check_update': 'zapretCheck',
  'zapret:install': 'zapretInstall',
  'zapret:remove': 'zapretRemove',
  'zapret2:check_update': 'zapret2Check',
  'zapret2:install': 'zapret2Install',
  'zapret2:remove': 'zapret2Remove',
  'byedpi:check_update': 'byedpiCheck',
  'byedpi:install': 'byedpiInstall',
  'byedpi:remove': 'byedpiRemove',
  'xray:check_update': 'xrayCheck',
  'xray:install': 'xrayInstall',
  'xray:list_versions': 'xrayCheck',
  'xray:remove': 'xrayRemove',
};

export function getComponentActionKey(
  component: Forkop.ComponentName,
  action: Forkop.ComponentAction | string,
): UpdatesActionKey | undefined {
  const baseAction = `${action}`.split('@')[0];
  return componentActionKeyMap[`${component}:${baseAction}`];
}
