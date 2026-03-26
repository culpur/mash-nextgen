# Adding Monitoring and SSO for a New Service

This guide walks through integrating a new service into mash-nextgen's Wazuh monitoring, fail2ban, and Authentik SSO layers. Not every service needs every step -- a simple container with no login endpoints only needs steps 1-3.

Throughout this guide, we use `myservice` as the placeholder name. Replace it with your actual service name.

## Prerequisites

- The service is already deployable via MASH or MDAD (it has an `<service>_enabled` variable)
- You have sample log output from the service (for writing decoders)
- You know the service's auth model (OIDC-capable? Login form? No auth?)

## Step 1: Add Service Detection

Edit `roles/wazuh-integration/defaults/main.yml` and add a detection variable in the appropriate section (MDAD or MASH):

```yaml
# MyService
wazuh_service_myservice: "{{ myservice_enabled | default(false) }}"
wazuh_dashboard_myservice: "{{ wazuh_dashboards_auto and wazuh_service_myservice }}"
wazuh_fail2ban_myservice: "{{ wazuh_fail2ban_auto and wazuh_service_myservice }}"
wazuh_myservice_log_path: "/opt/myservice/logs/myservice.log"
```

Key points:

- The variable name must be `wazuh_service_<name>` to match the existing convention
- Use `| default(false)` so the variable resolves even when the upstream variable is not defined
- Only add `wazuh_dashboard_*` if you are creating a dedicated dashboard
- Only add `wazuh_fail2ban_*` if the service has a login endpoint that can be brute-forced
- Set `wazuh_<name>_log_path` to where the service writes logs inside the container/host

If the service needs fail2ban settings, also add the threshold variables:

```yaml
fail2ban_myservice_maxretry: 5
fail2ban_myservice_bantime: 3600
fail2ban_myservice_findtime: 300
```

## Step 2: Write a Wazuh Decoder

Create `roles/wazuh-integration/templates/wazuh-decoders/myservice.xml.j2`:

```xml
<!-- Managed by mash-nextgen — MyService log decoder -->
<decoder name="myservice">
  <prematch>myservice|MyService</prematch>
</decoder>

<decoder name="myservice-login-failed">
  <parent>myservice</parent>
  <regex>authentication failed for user (\S+) from (\S+)</regex>
  <order>user, srcip</order>
</decoder>

<decoder name="myservice-login-success">
  <parent>myservice</parent>
  <regex>user (\S+) logged in from (\S+)</regex>
  <order>user, srcip</order>
</decoder>
```

Decoder writing guidelines:

- **Parent decoder**: The `<prematch>` must match a unique string that appears in every log line from this service. Use the service name or process name.
- **Child decoders**: Each child handles one event type (failed login, success, error, etc.)
- **Regex fields**: Always extract `srcip` for network events and `user` for auth events. These are used by rules for correlation.
- **Field order**: The `<order>` tag must list fields in the same order as the capture groups in `<regex>`.
- **Testing**: Paste real log lines into `wazuh-logtest` on the Wazuh manager to verify.

### Finding Log Formats

Check the service's documentation or run it locally and inspect the output:

```bash
# For Docker containers
docker logs <container_name> 2>&1 | head -50

# For file-based logs
tail -50 /path/to/service/log
```

Identify patterns for: authentication failures, authentication successes, errors, and any security-relevant events (file uploads, admin actions, API calls).

## Step 3: Write Wazuh Rules

Create `roles/wazuh-integration/templates/wazuh-rules/myservice.xml.j2`:

```xml
<!-- Managed by mash-nextgen — MyService security rules -->
<group name="myservice,authentication">

  <!-- Single failed login -->
  <rule id="100900" level="5">
    <decoded_as>myservice-login-failed</decoded_as>
    <description>MyService: Failed login for $(user) from $(srcip)</description>
    <group>authentication_failed,myservice</group>
  </rule>

  <!-- Brute force: 5+ failed logins from same IP in 5 minutes -->
  <rule id="100901" level="10" frequency="5" timeframe="300">
    <if_matched_sid>100900</if_matched_sid>
    <same_source_ip/>
    <description>MyService: Brute force attack from $(srcip)</description>
    <group>authentication_failed,myservice,brute_force</group>
    <mitre>
      <id>T1110</id>
    </mitre>
  </rule>

  <!-- Successful login -->
  <rule id="100902" level="3">
    <decoded_as>myservice-login-success</decoded_as>
    <description>MyService: Successful login for $(user) from $(srcip)</description>
    <group>authentication_success,myservice</group>
  </rule>

</group>
```

Rule writing guidelines:

- **Rule IDs**: Check `CONTRIBUTING.md` for allocated ranges. Pick the next available block of 10 in the 100xxx range.
- **Levels**: 3 = informational, 5 = low alert, 8 = notable, 10 = high (triggers active response), 12 = critical
- **Frequency rules**: Always use `<same_source_ip/>` for brute-force detection so unrelated IPs are not correlated
- **MITRE tags**: Add `<mitre><id>` for any rule that maps to a known technique (T1110 = brute force, T1136 = create account, T1190 = exploit public-facing, etc.)
- **Group names**: Use `service_name,category` format for consistency with existing rules

## Step 4: Create a Dashboard

Dashboards are exported as NDJSON from Wazuh Dashboard (OpenSearch Dashboards). To create one:

1. Log into Wazuh Dashboard
2. Create a new dashboard with visualizations for your service (auth events, error rates, geographic distribution, etc.)
3. Export: **Stack Management > Saved Objects > Select dashboard > Export**
4. Save the exported file as `roles/wazuh-integration/files/dashboards/myservice.ndjson`

Recommended visualizations for most services:

| Visualization | Type | Query |
|---------------|------|-------|
| Auth failures over time | Line chart | `rule.groups: myservice AND rule.groups: authentication_failed` |
| Top source IPs | Data table | `rule.groups: myservice` aggregated by `data.srcip` |
| Auth success vs failure | Pie chart | `rule.groups: myservice AND rule.groups: authentication*` |
| Event timeline | Area chart | `rule.groups: myservice` over time |
| Geographic distribution | Map | `rule.groups: myservice` with GeoIP on `data.srcip` |

If you do not have access to a running Wazuh Dashboard, create a minimal NDJSON with the index pattern and a saved search. The dashboard visualizations can be added later.

Also add the dashboard to the conditional deployment in `roles/wazuh-integration/tasks/dashboards.yml`:

```yaml
- name: Deploy MyService dashboard
  ansible.builtin.copy:
    src: dashboards/myservice.ndjson
    dest: /tmp/wazuh-dashboard-myservice.ndjson
    mode: '0644'
  when: wazuh_dashboard_myservice | default(false)
```

## Step 5: Add a Fail2ban Jail (If Applicable)

Only add a fail2ban jail if the service exposes a login endpoint that can be targeted by brute-force attacks. Services that use proxy auth via Authentik do not need their own jail (Traefik's jail covers them).

Create `roles/wazuh-integration/templates/fail2ban/jail-myservice.conf.j2`:

```ini
# Managed by mash-nextgen — MyService fail2ban jail
[myservice-auth]
enabled  = true
port     = http,https
filter   = myservice-auth
logpath  = {{ wazuh_myservice_log_path }}
maxretry = {{ fail2ban_myservice_maxretry }}
bantime  = {{ fail2ban_myservice_bantime }}
findtime = {{ fail2ban_myservice_findtime }}
action   = iptables-multiport[name=myservice, port="http,https", protocol=tcp]

# Filter definition
# Save as /etc/fail2ban/filter.d/myservice-auth.conf on the host:
#
# [Definition]
# failregex = authentication failed for user \S+ from <HOST>
# ignoreregex =
```

The `failregex` pattern should match the same log format as your Wazuh decoder's `<regex>`, using `<HOST>` as the fail2ban placeholder for the IP address.

Reference the jail in `roles/wazuh-integration/tasks/fail2ban.yml`:

```yaml
- name: Deploy MyService fail2ban jail
  ansible.builtin.template:
    src: fail2ban/jail-myservice.conf.j2
    dest: /etc/fail2ban/jail.d/myservice.conf
    mode: '0644'
  notify: restart fail2ban
  when: wazuh_fail2ban_myservice | default(false)
```

## Step 6: Add Authentik SSO (If Applicable)

If the service supports OIDC or can be protected by proxy auth, add SSO configuration.

### OIDC (Preferred)

For services with native OIDC/OAuth2 support, add to `roles/authentik-sso/defaults/main.yml`:

```yaml
# MyService (OIDC)
authentik_sso_myservice:
  enabled: "{{ myservice_enabled | default(false) }}"
  type: oauth2
  client_id: "myservice"
  redirect_uris:
    - "https://myservice.{{ domain }}/auth/oidc/callback"
  scopes: ["openid", "profile", "email"]
```

Key points:

- `client_id` must be unique across all providers
- `redirect_uris` must match exactly what the service sends during the OAuth flow (check the service's OIDC documentation)
- Most services need `openid`, `profile`, and `email` scopes

### Proxy Auth (Fallback)

For services without OIDC support, use Traefik ForwardAuth via Authentik's outpost:

```yaml
# MyService (proxy auth — no native OIDC)
authentik_sso_myservice:
  enabled: "{{ myservice_enabled | default(false) }}"
  type: proxy
  external_host: "https://myservice.{{ domain }}"
```

Proxy auth works by having Traefik check every request with Authentik before forwarding it to the backend. The service itself does not need any auth configuration.

### Services That Should NOT Get SSO

- **E2EE services** (CryptPad, PrivateBin) -- SSO would break the zero-knowledge model
- **Matrix clients** (Element, Cinny) -- They authenticate via Synapse, which has its own OIDC
- **Bridges and bots** -- They use Matrix homeserver tokens, not user-facing auth
- **Token-only services** (ntfy, Mosquitto) -- Protocol-level auth, not HTTP-based

## Step 7: Update Service Coverage

Edit `docs/service-coverage.md` and add a row for the new service in the appropriate table (MDAD or MASH):

```markdown
| **MyService** | W | F | A | S | Login monitoring + proxy auth |
```

Use the legend:
- `W` = Wazuh dashboard + decoder + rules
- `F` = Fail2ban jail
- `A` = Active-response (only if you added an active-response rule)
- `S` = Authentik SSO
- `-` = Not applicable

## Checklist

Before opening a PR, verify:

- [ ] `wazuh_service_<name>` variable added to `roles/wazuh-integration/defaults/main.yml`
- [ ] Decoder template created and valid XML (after Jinja2 rendering)
- [ ] Rules template created with IDs from an unallocated block
- [ ] Rule IDs documented in `CONTRIBUTING.md` allocation table
- [ ] Dashboard NDJSON exported and saved (or placeholder noted)
- [ ] Fail2ban jail created (if applicable) with regex matching decoder
- [ ] Authentik SSO config added (if applicable) with correct redirect URI
- [ ] `docs/service-coverage.md` updated
- [ ] All CI checks pass (`ansible-lint`, Jinja2 validation, XML validation)
- [ ] Sample log lines included in PR description for decoder testing

## Example: Complete Forgejo Integration

For a real-world reference, look at how Forgejo would be integrated:

- **Detection**: `wazuh_service_forgejo: "{{ forgejo_enabled | default(false) }}"` in defaults
- **Decoder**: Parses Forgejo's `[access]` log format for auth events
- **Rules**: 100220 (failed login), 100221 (brute force), 100222 (success), 100223 (repo created), 100224 (SSH key added)
- **Dashboard**: Auth failures, push/pull activity, repository creation timeline
- **Fail2ban**: `jail-forgejo.conf.j2` targeting the access log
- **SSO**: OIDC with `redirect_uris: ["https://git.{{ domain }}/user/oauth2/authentik/callback"]`
- **Coverage**: `| **Forgejo** | W | F | A | S | Git hosting -- auth + push/pull audit |`
