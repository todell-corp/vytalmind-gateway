-- JWT Claims Extractor for Envoy
-- Extracts JWT claims and adds them as custom headers for backend services

function envoy_on_request(request_handle)
  -- Get JWT payload from metadata (set by jwt_authn filter)
  local metadata = request_handle:metadata()

  if metadata == nil then
    return
  end

  local jwt_payload = metadata:get("jwt_payload")

  if jwt_payload == nil then
    request_handle:logInfo("No JWT payload found in metadata")
    return
  end

  -- Extract standard claims
  local sub = jwt_payload["sub"]
  local email = jwt_payload["email"]
  local name = jwt_payload["name"]
  local preferred_username = jwt_payload["preferred_username"]

  -- Extract custom claims (Keycloak specific)
  local realm_access = jwt_payload["realm_access"]
  local resource_access = jwt_payload["resource_access"]

  -- Add claims as custom headers
  if sub ~= nil then
    request_handle:headers():add("X-JWT-Sub", sub)
    request_handle:logInfo("Added X-JWT-Sub: " .. sub)
  end

  if email ~= nil then
    request_handle:headers():add("X-JWT-Email", email)
  end

  if name ~= nil then
    request_handle:headers():add("X-JWT-Name", name)
  end

  if preferred_username ~= nil then
    request_handle:headers():add("X-JWT-Username", preferred_username)
  end

  -- Extract roles from realm_access
  if realm_access ~= nil and realm_access["roles"] ~= nil then
    local roles = table.concat(realm_access["roles"], ",")
    request_handle:headers():add("X-JWT-Roles", roles)
    request_handle:logInfo("Added X-JWT-Roles: " .. roles)
  end

  -- Extract groups if present
  local groups = jwt_payload["groups"]
  if groups ~= nil and type(groups) == "table" then
    local groups_str = table.concat(groups, ",")
    request_handle:headers():add("X-JWT-Groups", groups_str)
    request_handle:logInfo("Added X-JWT-Groups: " .. groups_str)
  end

  -- Extract client roles from resource_access
  if resource_access ~= nil then
    local client_id = "edge-gateway"
    local client_access = resource_access[client_id]

    if client_access ~= nil and client_access["roles"] ~= nil then
      local client_roles = table.concat(client_access["roles"], ",")
      request_handle:headers():add("X-JWT-Client-Roles", client_roles)
    end
  end

  -- Add custom tenant/organization claim if present
  local tenant = jwt_payload["tenant_id"]
  if tenant ~= nil then
    request_handle:headers():add("X-JWT-Tenant", tenant)
  end
end

function envoy_on_response(response_handle)
  -- Optional: Add response processing here
end
