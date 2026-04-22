-- Server-side Aerotow Loader
local HttpService = game:GetService("HttpService")

local LICENSE_URL = "https://raw.githubusercontent.com/micklandman06-dot/aerotow/main/licenses.json"
local ENCRYPTED_SERVER_URL = "https://raw.githubusercontent.com/micklandman06-dot/aerotow/main/aerotow_server_encrypted.lua"

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
	warn("[Aerotow Server] Niet geladen: " .. err)
	return
end

local licenses = HttpService:JSONDecode(licenseRaw)
local license = licenses[PLACE_ID]

if not license then
	warn("[Aerotow Server] Geen licentie voor deze game")
	return
end

if not license.active then
	warn("[Aerotow Server] Uitgezet: " .. (license.reason or ""))
	return
end

if license.expires and os.date("!%Y-%m-%d") > license.expires then
	warn("[Aerotow Server] Trial verlopen")
	return
end

-- 📦 Encrypted server script ophalen
local encryptedServerCode, err2 = getData(ENCRYPTED_SERVER_URL)
if not encryptedServerCode then
	warn("[Aerotow Server] Encrypted server script niet geladen: " .. err2)
	return
end

-- 🔓 Decrypt server code
local decryptedServerCode = decrypt(encryptedServerCode, ENCRYPTION_KEY)

-- 🚀 Run decrypted server script
if decryptedServerCode and #decryptedServerCode > 0 then
	local success, result = pcall(function()
		local serverFunc = loadstring(decryptedServerCode)
		if serverFunc then
			serverFunc()
			print("[Aerotow Server] Successfully loaded and started")
		else
			warn("[Aerotow Server] Loadstring returned nil")
		end
	end)
	if not success then
		warn("[Aerotow Server] Error running script: " .. tostring(result))
	end
else
	warn("[Aerotow Server] Decrypted code is empty")
end