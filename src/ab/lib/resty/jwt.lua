local cjson = require "cjson"
local aes = require "resty.aes"
local evp = require "resty.evp"
local hmac = require "resty.hmac"
local resty_random = require "resty.random"

local _M = {_VERSION="0.1.1"}
local mt = {__index=_M}

local string_match= string.match
local string_rep = string.rep
local string_format = string.format
local string_sub = string.sub
local string_byte = string.byte
local table_concat = table.concat
local ngx_encode_base64 = ngx.encode_base64
local ngx_decode_base64 = ngx.decode_base64
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode

-- define string constants to avoid string garbage collection
local str_const = {
  regex_join_msg = '%s.%s',
  regex_join_delim = '([^%s]+)',
  regex_split_dot = '%.',
  regex_jwt_join_str = '%s.%s.%s',
  raw_underscore  = "raw_",
  dash = "-",
  empty = "",
  dotdot = '..',
  table  = "table",
  plus = '+',
  equal = '=',
  underscore = '_',
  slash = '/',
  header = "header",
  typ = "typ",
  JWT = "JWT",
  JWE = "JWE",
  payload = "payload",
  signature = "signature",
  encrypted_key = "encrypted_key",
  alg = "alg",
  enc = "enc",
  exp = "exp",
  nbf = "nbf",
  AES = "AES",
  cbc = "cbc",
  x5c = 'x5c',
  HS256 = "HS256",
  HS512 = "HS512",
  RS256 = "RS256",
  A128CBC_HS256 = "A128CBC_HS256",
  A256CBC_HS512 = "A256CBC_HS512",
  DIR = "DIR",
  reason = "reason",
  verified = "verified",
  number = "number",
  valid = "valid",
  internal_error = "internal error",
  everything_awesome = "everything is awesome~ :p"
}

-- @function split string
local function split_string(str, delim, maxNb)
  local result = {}
  local sep = string_format(str_const.regex_join_delim, delim)
  for m in str:gmatch(sep) do
    result[#result+1]=m
  end
  return result
end

--@function get the row part
--@param part_name
--@param jwt_obj
local function get_raw_part(part_name, jwt_obj)
  local raw_part = jwt_obj[str_const.raw_underscore .. part_name]
  if raw_part == nil then
    local part = jwt_obj[part_name]
    if part == nil then
      error({reason="missing part " .. part_name})
    end
    raw_part = _M:jwt_encode(part)
  end
  return raw_part
end


--@function decrypt payload
--@param secret_key to decrypt the payload
--@param encrypted payload
--@param encryption algorithm
--@param iv which was generated while encrypting the payload
--@return decrypted payloaf
local function decrypt_payload(secret_key, encrypted_payload, enc, iv_in )
  local decrypted_payload
  if enc == str_const.A128CBC_HS256 then
    local aes_128_cbc_with_iv = assert(aes:new(secret_key, str_const.AES, aes.cipher(128,str_const.cbc), {iv=iv_in} ))
    decrypted_payload=  aes_128_cbc_with_iv:decrypt(encrypted_payload)
  elseif enc == str_const.A256CBC_HS512 then
    local aes_256_cbc_with_iv = assert(aes:new(secret_key, str_const.AES, aes.cipher(256,str_const.cbc), {iv=iv_in} ))
    decrypted_payload=  aes_256_cbc_with_iv:decrypt(encrypted_payload)

  else
    return nil, "unsupported enc: " .. enc
  end
  if not  decrypted_payload then
    return nil, "invalid secret key"
  end
  return decrypted_payload
end

-- @function : encrypt payload using given secret
-- @param secret key to encrypt
-- @param algortim to use for encryption
-- @message  : data to be encrypted. It could be lua table or string
local function encrypt_payload(secret_key, message, enc )

  if enc == str_const.A128CBC_HS256 then
    local iv_rand =  resty_random.bytes(16,true)
    local aes_128_cbc_with_iv = assert(aes:new(secret_key, str_const.AES, aes.cipher(128,str_const.cbc), {iv=iv_rand} ))
    local encrypted = aes_128_cbc_with_iv:encrypt(message)
    return encrypted, iv_rand

  elseif enc == str_const.A256CBC_HS512 then
    local iv_rand =  resty_random.bytes(16,true)
    local aes_256_cbc_with_iv = assert(aes:new(secret_key, str_const.AES, aes.cipher(256,str_const.cbc), {iv=iv_rand} ))
    local encrypted = aes_256_cbc_with_iv:encrypt(message)
    return encrypted, iv_rand

  else
    return nil, nil , "unsupported enc: " .. enc
  end
end

--@function hmac_digest : generate hmac digest based on key for input message
--@param mac_key
--@param input message
--@return hmac digest
local function hmac_digest(enc, mac_key, message)
  if enc == str_const.A128CBC_HS256 then
    return hmac:new(mac_key, hmac.ALGOS.SHA256):final(message)
  elseif enc == str_const.A256CBC_HS512 then
    return hmac:new(mac_key, hmac.ALGOS.SHA512):final(message)
  else
    error({reason="unsupported enc: " .. enc})
  end
end

--@function dervice keys: it generates key if null based on encryption algorithm
--@param encryption type
--@param secret key
--@return secret key, mac key and encryption key
local function derive_keys(enc, secret_key)
  local key_size_bytes = 16
  if enc == str_const.A128CBC_HS256 then
    key_size_bytes = 16
  elseif enc == str_const.A256CBC_HS512 then
    key_size_bytes = 32
  end
  if not secret_key then
    secret_key =  resty_random.bytes(key_size_bytes,true)
  end
  if #secret_key ~= key_size_bytes then
    error({reason="The pre-shared content key must be ".. key_size_bytes})
  end
  local derived_key_size = key_size_bytes / 2
  mac_key = string_sub(secret_key, 1, derived_key_size)
  enc_key =string_sub(secret_key, derived_key_size)
  return secret_key, mac_key, enc_key
end

--@function parse_jwe
--@param pre-shared key
--@encoded-header
local function parse_jwe(preshared_key, encoded_header, encoded_encrypted_key, encoded_iv, encoded_cipher_text, encoded_auth_tag)


  local header = _M:jwt_decode(encoded_header, true)
  if not header then
    error({reason="invalid header: " .. encoded_header})
  end

  -- use preshared key if given otherwise decrypt the encoded key
  local key = preshared_key
  if not preshared_key then
    local encrypted_key = _M:jwt_decode(encoded_encrypted_key)
    if header.alg == str_const.DIR then
      error({reason="preshared key must not ne null"})
    else  -- implement algorithm to decrypt the key
      error({reason="invalid algorithm: " .. header.alg})
    end
  end

  local cipher_text = _M:jwt_decode(encoded_cipher_text)
  local iv =  _M:jwt_decode(encoded_iv)

  local basic_jwe = {
    internal = {
      encoded_header = encoded_header,
      cipher_text = cipher_text,
      key=key,
      iv = iv
    },
    header=header,
    signature=_M:jwt_decode(encoded_auth_tag)
  }


  local json_payload, err = decrypt_payload(key, cipher_text, header.enc, iv )
  if not json_payload then
    basic_jwe.reason = err

  else
    basic_jwe.payload = cjson.decode(json_payload)
    basic_jwe.internal.json_payload=json_payload
  end
  return basic_jwe
end

-- @function parse_jwt
-- @param encoded header
-- @param encoded
-- @param signature
-- @return jwt table
local function parse_jwt(encoded_header, encoded_payload, signature)
  local header = _M:jwt_decode(encoded_header, true)
  if not header then
    error({reason="failed to decrypt encoded header: " .. encoded_header})
  end

  local payload = _M:jwt_decode(encoded_payload, true)
  if not payload then
    error({reason="invalid payload: " .. encoded_payload})
  end

  local basic_jwt = {
    raw_header=encoded_header,
    raw_payload=encoded_payload,
    header=header,
    payload=payload,
    signature=signature
  }
  return basic_jwt

end

-- @function parse token - this can be JWE or JWT token
-- @param token string
-- @return jwt/jwe tables
local function parse(secret, token_str)
  local tokens = split_string(token_str, str_const.regex_split_dot)
  local num_tokens = #tokens
  if num_tokens == 4  then
    return parse_jwe(secret, tokens[1], "", tokens[2], tokens[3],  tokens[4])
  elseif num_tokens == 5 then
    return parse_jwe(secret, tokens[1], tokens[2], tokens[3],  tokens[4], tokens[5])
  else
    return  parse_jwt(tokens[1], tokens[2], tokens[3])
  end
end


--@function jwt encode : it converts into base64 encoded string. if input is a table, it convets into
-- json before converting to base64 string
--@param payloaf
--@return base64 encoded payloaf
function _M.jwt_encode(self, ori)
  if type(ori) == str_const.table then
    ori = cjson_encode(ori)
  end
  return ngx.encode_base64(ori):gsub(str_const.plus, str_const.dash):gsub(str_const.slash, str_const.underscore):gsub(str_const.equal, str_const.empty)
end



--@function jwt decode : decode bas64 encoded string
function _M.jwt_decode(self, b64_str, json_decode)
  b64_str = b64_str:gsub(str_const.dash, str_const.plus):gsub(str_const.underscore, str_const.slash)

  local reminder = #b64_str % 4
  if reminder > 0 then
    b64_str = b64_str .. string_rep(str_const.equal, 4 - reminder)
  end
  local data = ngx_decode_base64(b64_str)
  if not data then
    return nil
  end
  if json_decode then
    data = cjson_decode(data)
  end
  return data
end

--- Initialize the trusted certs
-- During RS256 verify, we'll make sure the
-- cert was signed by one of these
function _M.set_trusted_certs_file(self, filename)
  self.trusted_certs_file = filename
end
_M.trusted_certs_file = nil

--- Set a whitelist of allowed algorithms
-- E.g., jwt:set_alg_whitelist({RS256=1,HS256=1})
--
-- @param algorithms - A table with keys for the supported algorithms
--                     If the table is non-nil, during
--                     verify, the alg must be in the table
function _M.set_alg_whitelist(self, algorithms)
  self.alg_whitelist = algorithms
end

_M.alg_whitelist = nil


--@function sign jwe payload
--@param secret key : if used pre-shared or RSA key
--@param  jwe payload
--@return jwe token
local function sign_jwe(secret_key, jwt_obj)

  local enc = jwt_obj.header.enc
  local key, mac_key, enc_key = derive_keys(enc, secret_key)
  local json_payload = cjson.encode(jwt_obj.payload)
  local cipher_text, iv, err = encrypt_payload( key, json_payload, jwt_obj.header.enc )
  if err then
    error({reason="error while encryptiping payload. Error: " .. err})
  end
  local alg = jwt_obj.header.alg

  if alg ~= str_const.DIR then
    error({reason="unsupported alg: " .. alg})
  end
  -- remove type
  if jwt_obj.header.typ then
    jwt_obj.header.typ = nil
  end
  local encoded_header = _M:jwt_encode(jwt_obj.header)

  local encoded_header_length = #encoded_header  -- FIXME  : might be missin this logic
  local mac_input = table_concat({encoded_header , iv, cipher_text , encoded_header_length})
  local mac = hmac_digest(enc, mac_key, mac_input)
  -- TODO: implement logic for creating enc key and mac key and then encrypt key
  local encrypted_key
  if alg ==  str_const.DIR then
    encrypted_key = ""
  else
    error({reason="unsupported alg: " .. alg})
  end
  local auth_tag = string_sub(mac, 1, #mac/2)
  local jwe_table = {encoded_header, _M:jwt_encode(encrypted_key), _M:jwt_encode(iv),
                     _M:jwt_encode(cipher_text),   _M:jwt_encode(auth_tag)}
  return table_concat(jwe_table, '.', 1, 5)
end

--@function sign  : create a jwt/jwe signature from jwt_object
--@param secret key
--@param jwt/jwe payload
function _M.sign(self, secret_key, jwt_obj)
  -- header typ check
  local typ = jwt_obj[str_const.header][str_const.typ]
  -- Optional header typ check [See http://tools.ietf.org/html/draft-ietf-oauth-json-web-token-25#section-5.1]
  if typ ~= nil then
    if typ ~= str_const.JWT and typ ~= str_const.JWE then
      error({reason="invalid typ: " .. typ})
    end
  end

  if typ == str_const.JWE or jwt_obj.header.enc then
    return sign_jwe(secret_key, jwt_obj)
  end
  -- header alg check
  local raw_header = get_raw_part(str_const.header, jwt_obj)
  local raw_payload = get_raw_part(str_const.payload, jwt_obj)
  local message = string_format(str_const.regex_join_msg, raw_header , raw_payload)

  local alg = jwt_obj[str_const.header][str_const.alg]
  local signature = ""
  if alg == str_const.HS256 then
    signature = hmac:new(secret_key, hmac.ALGOS.SHA256):final(message)
  elseif alg == str_const.HS512 then
    signature = hmac:new(secret_key, hmac.ALGOS.SHA512):final(message)
  elseif alg == str_const.RS256 then
    local signer, err = evp.RSASigner:new(secret_key)
    if not signer then
      error({reason="signer error: " .. err})
    end
    signature = signer:sign(message, evp.CONST.SHA256_DIGEST)
  else
    error({reason="unsupported alg: " .. alg})
  end
  -- return full jwt string
  return string_format(str_const.regex_join_msg, message , _M:jwt_encode(signature))

end

--@function load jwt
--@param jwt string token
function _M.load_jwt(self, secret, jwt_str)
  local success, ret = pcall(parse, secret, jwt_str)
  if not success then
    return {
      valid=false,
      verified=false,
      reason=ret[str_const.reason] or "invalid jwt string"
    }
  end

  local jwt_obj = ret
  jwt_obj[str_const.verified] = false
  jwt_obj[str_const.valid] = true
  return jwt_obj
end

--@function validate_exp_nbf - validate expiry and not valid before
--@param jwt_obj
local function validate_exp_nbf(jwt_obj)
  local exp = jwt_obj[str_const.payload][str_const.exp]
  local nbf = jwt_obj[str_const.payload][str_const.nbf]

  if (exp ~= nil or nbf ~= nil ) and not jwt_obj[str_const.reason] then
    leeway = leeway or 0
    local now = ngx.now()

    if type(exp) == str_const.number and exp < (now - leeway) then
      jwt_obj[str_const.reason] = "jwt token expired at: " ..
              ngx.http_time(exp)
    elseif type(nbf) == str_const.number and nbf > (now + leeway) then
      jwt_obj[str_const.reason] = "jwt token not valid until: " ..
              ngx.http_time(nbf)
    end
  end
end
--@function verify jwe object
--@param secret
--@param jwt object
--@return owt object with reason whether verified or not
local function verify_jwe_obj(secret, jwt_obj)
  local key, mac_key, enc_key = derive_keys(jwt_obj.header.enc, jwt_obj.internal.key)
  local encoded_header = jwt_obj.internal.encoded_header

  local encoded_header_length = #encoded_header -- FIXME: Not sure how to get this
  local mac_input = table_concat({encoded_header , jwt_obj.internal.iv, jwt_obj.internal.cipher_text , encoded_header_length})
  local mac = hmac_digest(jwt_obj.header.enc, mac_key,  mac_input)
  local auth_tag = string_sub(mac, 1, #mac/2)

  if auth_tag ~= jwt_obj.signature then
    jwt_obj[str_const.reason] = "signature mismatch: " .. jwt_obj[str_const.signature]

  end
  jwt_obj.internal = nil
  jwt_obj.signature = nil

  if not jwt_obj[str_const.reason] then
    validate_exp_nbf(jwt_obj)
  end

  if not jwt_obj[str_const.reason] then
    jwt_obj[str_const.verified] = true
    jwt_obj[str_const.reason] = str_const.everything_awesome
  end

  return jwt_obj
end

--@function verify jwt object
--@param secret
--@param jwt_object
--@leeway
--@return verified jwt payload or jwt object with error code
function _M.verify_jwt_obj(self, secret, jwt_obj, leeway)
  if not jwt_obj.valid then
    return jwt_obj
  end
  -- if jwe, invoked verify jwe
  if jwt_obj[str_const.header][str_const.enc] then
    return verify_jwe_obj(secret, jwt_obj)
  end

  local alg = jwt_obj[str_const.header][str_const.alg]

  local jwt_str = string_format(str_const.regex_jwt_join_str, jwt_obj.raw_header , jwt_obj.raw_payload , jwt_obj.signature)



  if self.alg_whitelist ~= nil then
    if self.alg_whitelist[alg] == nil then
      return {verified=false, reason="whitelist unsupported alg: " .. alg}
    end
  end

  if alg == str_const.HS256 or alg == str_const.HS512 then
    local success, ret = pcall(_M.sign, self, secret, jwt_obj)
    if not success then
      -- syntax check
      jwt_obj[str_const.reason] = ret[str_const.reason] or str_const.internal_error
    elseif jwt_str ~= ret then
      -- signature check
      jwt_obj[str_const.reason] = "signature mismatch: " .. jwt_obj[str_const.signature]
    end
  elseif alg == str_const.RS256 then
    local cert
    if self.trusted_certs_file ~= nil then
      local cert, err = evp.Cert:new(secret)
      if not cert then
        jwt_obj[str_const.reason] = "Unable to load certificate" .. err
        return jwt_obj
      end
      -- Try validating against trusted CA's, then a cert passed as secret
      local trusted, err = cert:verify_trust(self.trusted_certs_file)
      if not trusted then
        jwt_obj[str_const.reason] = "Cert used to sign the JWT isn't trusted: " .. err
        return jwt_obj
      end
    elseif secret ~= nil then
      local err
      cert, err = evp.Cert:new(secret)
      if not cert then
        jwt_obj[str_const.reason] = "Decode secret is not a valid cert: " .. err
        return jwt_obj
      end
    else
      jwt_obj[str_const.reason] = "No trusted certs loaded"
      return jwt_obj
    end
    local verifier, err = evp.RSAVerifier:new(cert)
    if not verifier then
      -- Internal error case, should not happen...
      jwt_obj[str_const.reason] = "Failed to build verifier " .. err
      return jwt_obj
    end

    -- assemble jwt parts
    local raw_header = get_raw_part(str_const.header, jwt_obj)
    local raw_payload = get_raw_part(str_const.payload, jwt_obj)

    local message =string_format(str_const.regex_join_msg, raw_header ,  raw_payload)
    local sig = jwt_obj[str_const.signature]:gsub(str_const.dash, str_const.plus):gsub(str_const.underscore, str_const.slash)

    local verified, err = verifier:verify(message, _M:jwt_decode(sig, false), evp.CONST.SHA256_DIGEST)
    if not verified then
      jwt_obj[str_const.reason] = err
    end
  else
    jwt_obj[str_const.reason] = "Unsupported algorithm " .. alg
  end

  if not jwt_obj[str_const.reason] then
    validate_exp_nbf(jwt_obj)
  end

  if not jwt_obj[str_const.reason] then
    jwt_obj[str_const.verified] = true
    jwt_obj[str_const.reason] = str_const.everything_awesome
  end
  return jwt_obj

end


function _M.verify(self, secret, jwt_str, leeway, encrypted)

  jwt_obj = _M.load_jwt(self, secret, jwt_str)
  if not jwt_obj.valid then
    return {verified=false, reason=jwt_obj[str_const.reason]}
  end
  return  _M.verify_jwt_obj(self, secret, jwt_obj, leeway)

end

return _M