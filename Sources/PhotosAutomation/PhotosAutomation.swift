/// PhotosAutomation — a Swift library for driving the Apple Photos library
/// on macOS.
///
/// Two complementary transports behind one `PhotoService` facade:
/// - **PhotoKit** (``PhotoKitStore``): structured search, metadata, export,
///   import, albums, favorites.
/// - **AppleScript** (``NSAppleScriptRunner``): writing titles, descriptions,
///   and keywords, plus free-text search — the operations PhotoKit does not
///   expose.
