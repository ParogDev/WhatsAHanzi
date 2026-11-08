local mock = require("tests.wow_mock")

describe("Hash", function()
	local ns
	setup(function()
		mock.install()
		ns = {}
		mock.load(".", "Hash.lua", ns)
	end)

	it("matches the FNV-1a 32-bit reference vectors", function()
		assert.equal("811c9dc5", ns.Hash.fnv1a32(""))
		assert.equal("e40c292c", ns.Hash.fnv1a32("a"))
	end)

	it("hashes the UTF-8 bytes of Han text as the companion does", function()
		-- Values in tests/fixtures/hash_parity.json, read by the companion's parity test.
		assert.equal("86938da3", ns.Hash.fnv1a32("你好"))
		assert.equal("3043a59c", ns.Hash.fnv1a32("我在灰谷被联盟猎人射爆了"))
	end)

	it("agrees with the fixture file", function()
		local f = assert(io.open("tests/fixtures/hash_parity.json", "rb"))
		local json = f:read("*a")
		f:close()
		local n = 0
		for key, hex in json:gmatch('"([^"]*)"%s*:%s*"(%x+)"') do
			assert.equal(hex, ns.Hash.fnv1a32(key), "fixture key " .. key)
			n = n + 1
		end
		assert.equal(4, n)
	end)
end)
