-- Source configuration only. Loading this file never downloads or compiles tools.
-- Materialized to gframe/iOS/native_config.lua by apply_native_patches.py.
newoption { trigger = "ios-game-data", value = "directory", description = "Prepared, manifest-verified EDOPro game payload" }
newoption { trigger = "ios-bundle-id", value = "identifier", description = "Unsigned iOS bundle identifier", default = "com.vuminhdats.YuGiOhNativeIOS" }
newoption { trigger = "ios-python", value = "executable", description = "Python 3 interpreter for the resource copy phase", default = "/usr/bin/python3" }

local here = path.getabsolute(_SCRIPT_DIR)

local function require_file(filename)
	if not os.isfile(filename) then error("Missing iOS input: " .. filename, 0) end
end

local function configure(static_core)
	if not static_core or _OPTIONS["no-core"] or _OPTIONS["prebuilt-core"] then
		error("The iOS port requires the pinned static ocgcore + Lua source projects.", 0)
	end
	if _ACTION ~= "xcode4" then error("The native iOS port requires the xcode4 generator.", 0) end
	if #archs ~= 1 or archs[1] ~= "arm64" then
		error("This dependency recipe is arm64 iPhoneOS only; simulator archives are different inputs.", 0)
	end
	if not _OPTIONS["vcpkg-root"] then error("Supply the verified --vcpkg-root directory.", 0) end
	if not _OPTIONS["ios-game-data"] then error("Supply --ios-game-data with the prepared payload directory.", 0) end
	if not sounds.miniaudio then error("Use --sound=miniaudio for the native iOS audio backend.", 0) end
	local game = path.getabsolute(_OPTIONS["ios-game-data"])
	local deps = get_vcpkg_root_path("arm64")
	require_file(path.join(game, "package-manifest.json"))
	require_file(path.join(game, "offline-ai/offline_ai.js"))
	require_file(path.join(deps, "include/irrlicht/irrlicht.h"))
	for _, name in ipairs({"Irrlicht", "sqlite3", "event", "event_pthreads", "git2", "ssh2", "ssl", "crypto", "fmt", "curl", "freetype", "png", "bz2", "jpeg", "z"}) do
		require_file(path.join(deps, "lib/lib" .. name .. ".a"))
	end
	filter "system:ios"
		systemversion "16.0"
		architecture "ARM64"
		files { path.join(here, "*.mm"), path.join(here, "*.h") }
		links { "CoreGraphics.framework", "CoreText.framework", "ImageIO.framework", "JavaScriptCore.framework",
			"Security.framework", "SystemConfiguration.framework", "jpeg", "z" }
		xcodebuildsettings {
			["PRODUCT_BUNDLE_IDENTIFIER"] = _OPTIONS["ios-bundle-id"],
			["INFOPLIST_FILE"] = path.join(here, "../ios-Info.plist"),
			["GENERATE_INFOPLIST_FILE"] = "NO",
			["IPHONEOS_DEPLOYMENT_TARGET"] = "16.0",
			["SDKROOT"] = "iphoneos",
			["SUPPORTED_PLATFORMS"] = "iphoneos",
			["ARCHS"] = "arm64",
			["ONLY_ACTIVE_ARCH"] = "NO",
			["TARGETED_DEVICE_FAMILY"] = "1,2",
			["SUPPORTS_MACCATALYST"] = "NO",
			["SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD"] = "NO",
			["CODE_SIGNING_ALLOWED"] = "NO",
			["CODE_SIGNING_REQUIRED"] = "NO",
			["CODE_SIGN_IDENTITY"] = "",
			["ENABLE_BITCODE"] = "NO",
			["CLANG_ENABLE_OBJC_ARC"] = "NO", -- Existing upstream iOS glue uses manual retain/release.
			["ENABLE_USER_SCRIPT_SANDBOXING"] = "NO", -- The manifest enumerates the complete resource tree at phase runtime.
			["EDOPRO_GAME_SOURCE"] = game,
			["EDOPRO_ICON_SOURCE"] = path.getabsolute("../../ios-assets", here),
			["EDOPRO_RESOURCE_SCRIPT"] = path.join(here, "copy_bundle_resources.py"),
			["EDOPRO_PYTHON"] = _OPTIONS["ios-python"],
			["MARKETING_VERSION"] = "1.0.0",
			["CURRENT_PROJECT_VERSION"] = "1"
		}
		postbuildcommands {
			'"${EDOPRO_PYTHON}" "${EDOPRO_RESOURCE_SCRIPT}" --source "${EDOPRO_GAME_SOURCE}" --icons "${EDOPRO_ICON_SOURCE}" --bundle-root "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"'
		}
	filter { "system:ios", "configurations:Release" }
		links { "png", "bz2" }
	filter { "system:ios", "configurations:Debug" }
		links { "png16d", "bz2d" }
	filter { "system:ios", "files:iOS/**.mm" }
		compileas "Objective-C++"
	filter {}
end

local function configure_libraries()
	-- Reopen the existing source targets, without changing their files or linkage.
	for _, name in ipairs({ "lua", "ocgcore", "clzma" }) do
		project(name)
		filter "system:ios"
			systemversion "16.0"
			xcodebuildsettings {
				["SDKROOT"] = "iphoneos", ["SUPPORTED_PLATFORMS"] = "iphoneos",
				["IPHONEOS_DEPLOYMENT_TARGET"] = "16.0", ["ARCHS"] = "arm64",
				["CODE_SIGNING_ALLOWED"] = "NO", ["ENABLE_BITCODE"] = "NO"
			}
			if name == "lua" then
				-- Core callbacks rely on C++ stack unwinding, not longjmp across C++ frames.
				exceptionhandling "On"
				cppdialect "C++17"
				xcodebuildsettings {
					["GCC_ENABLE_CPP_EXCEPTIONS"] = "YES",
					["GCC_PREFIX_HEADER"] = path.getabsolute("../../ocgcore/lua/luaconf-customize.h", here),
					["GCC_PRECOMPILE_PREFIX_HEADER"] = "NO"
				}
			end
		filter {}
	end
	project "ygopro"
end

return { configure = configure, configure_libraries = configure_libraries }
