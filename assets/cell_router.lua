-- envoy_on_request is the main entry point for the Lua filter.
function envoy_on_request(request_handle)
  -- We need to inspect the request body, which isn't available immediately.
  -- This call tells Envoy to buffer the body and call our process_request
  -- function once it's fully received.
  request_handle:body(1024 * 1024) -- Buffer up to 1MB
end

-- This function contains the core routing logic and is called after the
-- request body has been buffered.
function process_request(request_handle)
  local path = request_handle:path()
  local headers = request_handle:headers()
  local body_bytes = request_handle:body():getBytes(0, request_handle:body():length())

  -- Default upstream cluster if no rules match. Could be an error service.
  local upstream_cluster = "common-cell-cluster"

  -- Attempt to parse the body as JSON.
  -- json.lua library would be provided in the Envoy build or ConfigMap.
  -- For this example, we'll use a simple string find for demonstration.
  local body_str = tostring(body_bytes)

  -- Rule 1 & 2: Simple API Path Routing
  if path:find("^/products") then
    upstream_cluster = "common-cell-cluster"
  elseif path:find("^/closed/summary") then
    -- Assuming TDS-related services are in the Corporate Cell
    upstream_cluster = "corporate-cell-cluster"
  else
    -- Rules 3-5: Payload-based routing (Fast Paths)
    local product_code = get_json_field(body_str, "productCode")
    local account_num = get_json_field(body_str, "accountNumber")

    if product_code == "010" or product_code == "011" or product_code == "025" then
      -- Rule 3: High-volume retail products
      upstream_cluster = "retail-cell-cluster"
    elseif product_code == "391" then
      -- Rule 4: Specific corporate product
      upstream_cluster = "corporate-cell-cluster"
    elseif (product_code == "020" or product_code == "021" or product_code == "022") and
           (account_num:find("^0072") or account_num:find("^060[0-9]")) then
      -- Rule 5: Paylah wallet products with specific account prefixes
      upstream_cluster = "paylah-cell-cluster"
    else
      -- Rule 6 & 7: Fallback to Cell Localization Service (Dynamic Lookup)
      local cls_headers = {
        [":method"] = "POST",
        [":path"] = "/v1/locate",
        [":authority"] = "cell-localization-service.common.svc.cluster.local",
        ["content-type"] = "application/json"
      }
      -- Pass original headers for context if needed
      local cls_body = '{"accountNumber": "' .. account_num .. '"}'

      -- Make an ASYNCHRONOUS call to the internal CLS.
      -- The original request is paused until the CLS responds.
      -- The 'on_cls_response' function is the callback.
      request_handle:httpCall(
        "common-cell-cluster",
        cls_headers,
        cls_body,
        5000, -- 5 second timeout
        true, -- Asynchronous call
        "on_cls_response"
      )
      -- Stop further processing in this function; the callback will handle it.
      return
    end
  end

  -- If a fast-path rule matched, route the request immediately.
  request_handle:routeTo(upstream_cluster, headers)
end

-- Callback function to handle the response from the Cell Localization Service
function on_cls_response(response_headers, response_body_bytes, request_handle)
  local headers = request_handle:headers()
  local upstream_cluster = "error-service-cluster" -- Default on failure

  if response_headers:get(":status") == "200" then
    local response_str = tostring(response_body_bytes)
    local target_cell = get_json_field(response_str, "targetCell") -- e.g., "retail-cell"
    if target_cell then
      -- The CLS told us where to go. The cluster name is constructed from the response.
      upstream_cluster = target_cell .. "-cluster"
    end
  end

  -- Route the original request to the cluster determined by the CLS.
  request_handle:routeTo(upstream_cluster, headers)
end

-- Helper function to crudely extract a field from a JSON string.
-- In a real implementation, a proper JSON library should be used.
function get_json_field(json_str, key)
  local value = json_str:match('"' .. key .. '":"(.-)"')
  if value then return value end
  return ""
end
