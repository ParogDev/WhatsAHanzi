-- Line identity shared with the companion: FNV-1a, 32 bits, over the UTF-8 bytes of the message body,
-- rendered as 8 lowercase hex digits. Both sides pin the same vectors (tests/fixtures/hash_parity.json).
local _, ns = ...
local Hash = {}
ns.Hash = Hash

local OFFSET = 2166136261
local PRIME_LOW = 403 -- 16777619 = 2^24 + 403; the high part is a shift by 24 bits
local MOD = 4294967296

local band, bxor = bit.band, bit.bxor

-- h * 16777619 mod 2^32 without leaving the double's exact range: h * 403 stays under 2^41, and
-- (h << 24) mod 2^32 is the low byte of h moved up.
local function mulPrime(h)
	return (h * PRIME_LOW + band(h, 0xff) * 16777216) % MOD
end

function Hash.fnv1a32(s)
	local h = OFFSET
	for i = 1, #s do
		h = bxor(h, s:byte(i)) % MOD
		h = mulPrime(h)
	end
	return ("%08x"):format(h)
end
