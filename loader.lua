local HttpService = game:GetService("HttpService")

local LICENSE_URL = "https://api.github.com/repos/micklandman06-dot/aerotow/contents/licenses.json"
local ENCRYPTED_CORE_URL = "https://raw.githubusercontent.com/micklandman06-dot/aerotow/main/aerotow_encrypted.lua"

local PLACE_ID = tostring(game.PlaceId)
local ENCRYPTION_KEY = "aerotow_secret_key_2026_xyz"

local function getData(url)
	local success, response = pcall(function()
		return HttpService:GetAsync(url .. "?t=" .. os.time())
	end)

	if not success then
		return nil, "Kon niet verbinden"
	end

	return response
end

local function decrypt(encryptedText, key)
	local decoded = ""
	local success, result = pcall(function()
		return HttpService:JSONDecode('"' .. encryptedText .. '"')
	end)

	if success then
		encryptedText = result
	end

	for i = 1, #encryptedText do
		local byte = string.byte(encryptedText, i)
		local keyByte = string.byte(key, (i-1) % #key + 1)
		decoded = decoded .. string.char(bit32.bxor(byte, keyByte))
	end
	return decoded
end

-- 🔑 Licentie check
local licenseRaw, err = getData(LICENSE_URL)
if not licenseRaw then
	warn("[Aerotow] Niet geladen: " .. err)
	return
end

local licenseData = HttpService:JSONDecode(licenseRaw)
local licenseContent = licenseData.content
local decodedContent = HttpService:JSONDecode(HttpService:JSONDecode('"' .. licenseContent .. '"'))

local licenses = decodedContent
local license = licenses[PLACE_ID]

if not license then
	warn("[Aerotow] Geen licentie voor deze game")
	return
end

if not license.active then
	warn("[Aerotow] Uitgezet: " .. (license.reason or ""))
	return
end

if license.expires and os.date("!%Y-%m-%d") > license.expires then
	warn("[Aerotow] Trial verlopen")
	return
end

-- 📦 Encrypted script ophalen
local encryptedCode, err2 = getData(ENCRYPTED_CORE_URL)
if not encryptedCode then
	warn("[Aerotow] Encrypted script niet geladen: " .. err2)
	return
end

-- 🔓 Decrypt code
local decryptedCode = decrypt(encryptedCode, ENCRYPTION_KEY)

-- 🚀 Run decrypted script
local func = loadstring(decryptedCode)
if func then
	func()()
else
	warn("[Aerotow] Loadstring error - decryption failed")
end</content>
<parameter name="filePath">/workspaces/aerotow/loader.lua