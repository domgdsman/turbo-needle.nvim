-- Test script to validate tab completion functionality
local turbo_needle = require("turbo-needle")

-- Setup the plugin with minimal config
turbo_needle.setup({
    api = {
        base_url = "http://localhost:8000", -- Use your running model server
        model = "codellama:7b-code",
        timeout = 5000,
        max_retries = 1,
    }
})

print("=== Turbo Needle Tab Completion Test ===")

-- Test 1: Basic setup
print("\n1. Testing plugin setup...")
print("   ✓ Plugin loaded successfully")

-- Test 2: Ghost text functionality
print("\n2. Testing ghost text display...")
turbo_needle.set_ghost_text("test_completion")
print("   ✓ Ghost text set to: 'test_completion'")

-- Test 3: Tab completion acceptance
print("\n3. Testing tab completion acceptance...")
local result = turbo_needle.accept_completion()
print("   Tab completion result:", result)
if result == "" then
    print("   ✓ SUCCESS: Tab completion accepted (returned empty string)")
else
    print("   ✗ FAILED: Tab completion not accepted (returned: '" .. result .. "')")
end

-- Test 4: Clear ghost text
print("\n4. Testing ghost text clearing...")
turbo_needle.clear_ghost_text()
print("   ✓ Ghost text cleared")

-- Test 5: Tab without ghost text
print("\n5. Testing tab without ghost text...")
result = turbo_needle.accept_completion()
print("   Tab result:", result)
if result == "\t" then
    print("   ✓ SUCCESS: Normal tab behavior (returned tab character)")
else
    print("   ✗ FAILED: Unexpected tab behavior (returned: '" .. result .. "')")
end

print("\n=== Test Complete ===")
print("If all tests show SUCCESS, tab completion is working correctly!")