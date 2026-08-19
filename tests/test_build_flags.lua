local T = require("tests.testlib")

local suite = T.suite("build flags")

suite.test("defaults to a non-release dev build when build_info is absent", function()
    package.loaded.build_info = nil
    package.loaded.build_flags = nil
    local BuildFlags = require("build_flags")
    T.assert_false(BuildFlags.release, "release should be false")
    T.assert_eq(BuildFlags.timestamp, nil, "timestamp should be absent")
end)

suite.test("reads a release stamp from build_info", function()
    package.loaded.build_info = { release = true }
    package.loaded.build_flags = nil
    local BuildFlags = require("build_flags")
    T.assert_true(BuildFlags.release, "release should be true")
    T.assert_eq(BuildFlags.timestamp, nil, "release builds omit the timestamp")
end)

suite.test("reads a CIA timestamp when not a release build", function()
    package.loaded.build_info = { timestamp = "08/18, 10:51AM CST" }
    package.loaded.build_flags = nil
    local BuildFlags = require("build_flags")
    T.assert_false(BuildFlags.release, "release should be false")
    T.assert_eq(BuildFlags.timestamp, "08/18, 10:51AM CST", "timestamp should pass through")
end)

return suite
