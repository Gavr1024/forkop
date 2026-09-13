import { describe, expect, it } from 'vitest';
import {
  formatMaskedSingBoxConfig,
  formatMaskedXrayConfig,
  maskGlobalCheckText,
  maskSingBoxConfigValue,
  maskXrayConfigValue,
} from '../helpers/maskDiagnostics';

describe('diagnostic masking', () => {
  it('masks sensitive sing-box keys without mutating the original config', () => {
    const config = {
      outbounds: [
        {
          type: 'vless',
          tag: 'proxy',
          server: 'example.com',
          server_port: 443,
          uuid: 'client-id',
          tls: {
            enabled: true,
            server_name: 'example.com',
          },
        },
      ],
      route: {
        rules: [{ domain_suffix: ['example.org'], outbound: 'proxy' }],
      },
    };

    expect(maskSingBoxConfigValue(config)).toEqual({
      outbounds: [
        {
          type: 'vless',
          tag: 'proxy',
          server: 'MASKED',
          server_port: 'MASKED',
          uuid: 'MASKED',
          tls: {
            enabled: true,
            server_name: 'MASKED',
          },
        },
      ],
      route: {
        rules: [{ domain_suffix: 'MASKED', outbound: 'proxy' }],
      },
    });
    expect(config.outbounds[0].server).toBe('example.com');
  });

  it('formats masked sing-box config from a raw JSON string', () => {
    const masked = formatMaskedSingBoxConfig(
      '{"inbounds":[{"listen":"127.0.0.1","listen_port":2080}]}',
    );

    expect(masked).toContain('"listen": "MASKED"');
    expect(masked).toContain('"listen_port": "MASKED"');
  });

  it('masks sensitive xray keys without mutating the original config', () => {
    const config = {
      outbounds: [
        {
          protocol: 'vless',
          tag: 'proxy',
          settings: {
            address: '194.221.250.50',
            port: 443,
            id: 'client-id',
            encryption: 'none',
            flow: 'xtls-rprx-vision',
          },
          streamSettings: {
            realitySettings: {
              publicKey: 'pbk-secret',
              shortId: '6ba85179',
              serverName: 'yahoo.com',
              fingerprint: 'chrome',
            },
          },
        },
      ],
    };

    expect(maskXrayConfigValue(config)).toEqual({
      outbounds: [
        {
          protocol: 'vless',
          tag: 'proxy',
          settings: {
            address: 'MASKED',
            port: 'MASKED',
            id: 'MASKED',
            encryption: 'MASKED',
            flow: 'MASKED',
          },
          streamSettings: {
            realitySettings: {
              publicKey: 'MASKED',
              shortId: 'MASKED',
              serverName: 'MASKED',
              fingerprint: 'MASKED',
            },
          },
        },
      ],
    });
    expect(config.outbounds[0].settings.id).toBe('client-id');
  });

  it('formats masked xray config from a raw JSON string', () => {
    const masked = formatMaskedXrayConfig(
      '{"inbounds":[{"listen":"127.0.0.1","port":10808}]}',
    );

    expect(masked).toContain('"listen": "MASKED"');
    expect(masked).toContain('"port": "MASKED"');
  });

  it('masks sensitive global check UCI values while keeping visible structure stable', () => {
    const raw = [
      "config section 'main'",
      "\toption proxy_string 'vless://secret@example.com:443'",
      "\toption hwid 'device-secret'",
      "\tlist domain 'example.com'",
      "\toption outbound_json '{",
      '  "server": "example.com",',
      "}'",
      "config interface 'lan'",
      "\toption ipaddr '192.168.1.1'",
      "\toption netmask '255.255.255.0'",
      "config interface 'wan'",
      "\toption username 'provider-user'",
      "\toption password 'provider-password'",
      "config subscription_url 'sub1'",
      "\toption url 'https://user:password@example.com/subscription?token=secret'",
      "config interface 'wireguard_wan'",
      "\toption private_key 'wireguard-private-secret'",
      '',
    ].join('\n');

    const masked = maskGlobalCheckText(raw);

    expect(masked.split('\n')).toHaveLength(raw.split('\n').length);
    expect(masked).not.toContain('vless://secret');
    expect(masked).not.toContain('device-secret');
    expect(masked).not.toContain('example.com",');
    expect(masked).not.toContain('192.168.1.1');
    expect(masked).not.toContain('provider-password');
    expect(masked).not.toContain('token=secret');
    expect(masked).not.toContain('wireguard-private-secret');
    expect(masked).toContain("option proxy_string 'MASKED'");
    expect(masked).toContain("option ipaddr 'MASKED'");
    expect(masked).toContain("option url 'MASKED'");
    expect(masked).toContain("option private_key 'MASKED'");
  });
});
