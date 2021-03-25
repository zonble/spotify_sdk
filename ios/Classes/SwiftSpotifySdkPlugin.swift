import Flutter
import SpotifyiOS

public class SwiftSpotifySdkPlugin: NSObject, FlutterPlugin {

    private var appRemote: SPTAppRemote?
    private var connectionStatusHandler: ConnectionStatusHandler?
    private var playerStateHandler: PlayerStateHandler?
    private var playerContextHandler: PlayerContextHandler?
    private static var playerStateChannel: FlutterEventChannel?
    private static var playerContextChannel: FlutterEventChannel?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let spotifySDKChannel = FlutterMethodChannel(name: "spotify_sdk", binaryMessenger: registrar.messenger())
        let connectionStatusChannel = FlutterEventChannel(name: "connection_status_subscription", binaryMessenger: registrar.messenger())
        playerStateChannel = FlutterEventChannel(name: "player_state_subscription", binaryMessenger: registrar.messenger())
        playerContextChannel = FlutterEventChannel(name: "player_context_subscription", binaryMessenger: registrar.messenger())

        let instance = SwiftSpotifySdkPlugin()
        registrar.addApplicationDelegate(instance)
        registrar.addMethodCallDelegate(instance, channel: spotifySDKChannel)

        instance.connectionStatusHandler = ConnectionStatusHandler()

        connectionStatusChannel.setStreamHandler(instance.connectionStatusHandler)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        var defaultPlayAPICallback: SPTAppRemoteCallback {
            get {
                return {_, error in
                    if let error = error {
                        result(FlutterError(code: "PlayerAPI Error", message: error.localizedDescription, details: nil))
                    } else {
                        result(true)
                    }
                }
            }
        }

        switch call.method {
        case SpotfySdkConstants.methodConnectToSpotify:
            guard let swiftArguments = call.arguments as? [String:Any],
                let clientID = swiftArguments[SpotfySdkConstants.paramClientId] as? String,
                let url = swiftArguments[SpotfySdkConstants.paramRedirectUrl] as? String else {
                    result(FlutterError(code: "Arguments Error", message: "One or more arguments are missing", details: nil))
                    return
            }
            if let accessToken = swiftArguments[SpotfySdkConstants.paramAccessToken] as? String, let appRemote = appRemote {
                appRemote.connectionParameters.accessToken = accessToken
                appRemote.connect()
            } else {
                let scope = swiftArguments[SpotfySdkConstants.scope] as? [String] ?? [String]()
                connectionStatusHandler?.connectionResult = result
                do {
                    try connectToSpotify(clientId: clientID, redirectURL: url, scope: scope)
                }
                catch {
                    result(FlutterError(code: "CouldNotFindSpotifyApp", message: "The Spotify app is not installed on the device", details: nil))
                    return
                }
            }
        case SpotfySdkConstants.methodGetAuthenticationToken:
            guard let swiftArguments = call.arguments as? [String:Any],
                let clientID = swiftArguments[SpotfySdkConstants.paramClientId] as? String,
                let url = swiftArguments[SpotfySdkConstants.paramRedirectUrl] as? String else {
                    result(FlutterError(code: "Arguments Error", message: "One or more arguments are missing", details: nil))
                    return
            }
            if let appRemote = appRemote, let accessToken = appRemote.connectionParameters.accessToken {
                result(accessToken)
                return
            }
            connectionStatusHandler?.tokenResult = result
            do {
                try connectToSpotify(clientId: clientID, redirectURL: url)
            }
            catch {
                result(FlutterError(code: "CouldNotFindSpotifyApp", message: "The Spotify app is not installed on the device", details: nil))
                return
            }
        case SpotfySdkConstants.methodGetImage:
            guard let appRemote = appRemote else {
                result(FlutterError(code: "Connection Error", message: "AppRemote is null", details: nil))
                return
            }
            guard let swiftArguments = call.arguments as? [String:Any],
                let paramImageUri = swiftArguments[SpotfySdkConstants.paramImageUri] as? String,
                let paramImageDimension = swiftArguments[SpotfySdkConstants.paramImageDimension] as? Int else {
                    result(FlutterError(code: "Arguments Error", message: "One or more arguments are missing", details: nil))
                    return
            }

            class ImageObject: NSObject, SPTAppRemoteImageRepresentable {
                var imageIdentifier: String = ""
            }

            let imageObject = ImageObject()
            imageObject.imageIdentifier = paramImageUri
            appRemote.imageAPI?.fetchImage(forItem: imageObject, with: CGSize(width: paramImageDimension, height: paramImageDimension), callback: { (image, error) in
                guard error == nil else {
                    result(FlutterError(code: "ImageAPI Error", message: error?.localizedDescription, details: nil))
                    return
                }
                guard let imageData = (image as? UIImage)?.pngData() else {
                    result(FlutterError(code: "ImageAPI Error", message: "Image is empty", details: nil))
                    return
                }
                result(imageData)
            })
        case SpotfySdkConstants.methodGetPlayerState:
            guard let appRemote = appRemote else {
                result(FlutterError(code: "Connection Error", message: "AppRemote is null", details: nil))
                return
            }
            
            appRemote.playerAPI?.getPlayerState({ (playerState, error) in
                guard error == nil else {
                    result(FlutterError(code: "PlayerAPI Error", message: error?.localizedDescription, details: nil))
                    return
                }
                guard let playerState = playerState as? SPTAppRemotePlayerState else {
                    result(FlutterError(code: "PlayerAPI Error", message: "PlayerState is empty", details: nil))
                    return
                }
                result(State.playerStateDictionary(playerState).json)
            })
        case SpotfySdkConstants.methodDisconnectFromSpotify:
            appRemote?.disconnect()
//            appRemote?.connectionParameters.accessToken = nil
            result(true)
        case SpotfySdkConstants.methodPlay:
            guard let appRemote = appRemote else {
                result(FlutterError(code: "Connection Error", message: "AppRemote is null", details: nil))
                return
            }
            guard let swiftArguments = call.arguments as? [String:Any],
                let uri = swiftArguments[SpotfySdkConstants.paramSpotifyUri] as? String else {
                    result(FlutterError(code: "URI Error", message: "No URI was specified", details: nil))
                    return
            }
            let asRadio: Bool = (swiftArguments[SpotfySdkConstants.paramAsRadio] as? Bool) ?? false
            appRemote.playerAPI?.play(uri, asRadio: asRadio, callback: defaultPlayAPICallback)
        case SpotfySdkConstants.methodPause:
            guard let appRemote = appRemote else {
                result(FlutterError(code: "Connection Error", message: "AppRemote is null", details: nil))
                return
            }
            appRemote.playerAPI?.pause(defaultPlayAPICallback)
        case SpotfySdkConstants.methodResume:
            guard let appRemote = appRemote else {
                result(FlutterError(code: "Connection Error", message: "AppRemote is null", details: nil))
                return
            }
            appRemote.playerAPI?.resume(defaultPlayAPICallback)
        case SpotfySdkConstants.methodSkipNext:
            guard let appRemote = appRemote else {
                result(FlutterError(code: "Connection Error", message: "AppRemote is null", details: nil))
                return
            }
            appRemote.playerAPI?.skip(toNext: defaultPlayAPICallback)
        case SpotfySdkConstants.methodSkipPrevious:
            guard let appRemote = appRemote else {
                result(FlutterError(code: "Connection Error", message: "AppRemote is null", details: nil))
                return
            }
            appRemote.playerAPI?.skip(toPrevious: { (spotifyResult, error) in
                if let error = error {
                    result(FlutterError(code: "PlayerAPI Error", message: error.localizedDescription, details: nil))
                    return
                }
                result(true)
            })
        case SpotfySdkConstants.methodAddToLibrary:
            guard let appRemote = appRemote else {
                result(FlutterError(code: "Connection Error", message: "AppRemote is null", details: nil))
                return
            }
            guard let swiftArguments = call.arguments as? [String:Any],
                let uri = swiftArguments[SpotfySdkConstants.paramSpotifyUri] as? String else {
                    result(FlutterError(code: "URI Error", message: "No URI was specified", details: nil))
                    return
            }
            appRemote.userAPI?.addItemToLibrary(withURI: uri, callback: defaultPlayAPICallback)
        case SpotfySdkConstants.methodRemoveFromLibrary:
            guard let appRemote = appRemote else {
                result(FlutterError(code: "Connection Error", message: "AppRemote is null", details: nil))
                return
            }
            guard let swiftArguments = call.arguments as? [String:Any],
                let uri = swiftArguments[SpotfySdkConstants.paramSpotifyUri] as? String else {
                    result(FlutterError(code: "URI Error", message: "No URI was specified", details: nil))
                    return
            }
            appRemote.userAPI?.removeItemFromLibrary(withURI: uri, callback: defaultPlayAPICallback)
        case SpotfySdkConstants.methodQueueTrack:
            guard let appRemote = appRemote else {
                result(FlutterError(code: "Connection Error", message: "AppRemote is null", details: nil))
                return
            }
            guard let swiftArguments = call.arguments as? [String:Any],
                let uri = swiftArguments[SpotfySdkConstants.paramSpotifyUri] as? String else {
                    result(FlutterError(code: "URI Error", message: "No URI was specified", details: nil))
                    return
            }
            appRemote.playerAPI?.enqueueTrackUri(uri, callback: defaultPlayAPICallback)
        case SpotfySdkConstants.methodSeekTo:
            guard let appRemote = appRemote else {
                result(FlutterError(code: "Connection Error", message: "AppRemote is null", details: nil))
                return
            }
            guard let swiftArguments = call.arguments as? [String:Any],
                let position = swiftArguments[SpotfySdkConstants.paramPositionedMilliseconds] as? Int else {
                    result(FlutterError(code: "Position error", message: "No URI was specified", details: nil))
                    return
            }
            appRemote.playerAPI?.seek(toPosition: position, callback: defaultPlayAPICallback)
        case SpotfySdkConstants.methodGetCrossfadeState:
            guard let appRemote = appRemote else {
                result(FlutterError(code: "Connection Error", message: "AppRemote is null", details: nil))
                return
            }
            appRemote.playerAPI?.getCrossfadeState({ (crossfadeState, error) in
                guard error == nil else {
                    result(FlutterError(code: "PlayerAPI Error", message: error?.localizedDescription, details: nil))
                    return
                }
                guard let crossfadeState = crossfadeState as? SPTAppRemoteCrossfadeState else {
                    result(FlutterError(code: "PlayerAPI Error", message: "PlayerState is empty", details: nil))
                    return
                }
                result(State.crossfadeStateDictionary(crossfadeState).json)
            })
        case SpotfySdkConstants.methodSetShuffle:
            guard let appRemote = appRemote else {
                result(FlutterError(code: "Connection Error", message: "AppRemote is null", details: nil))
                return
            }
            guard let swiftArguments = call.arguments as? [String:Any],
                let shuffle = swiftArguments[SpotfySdkConstants.paramShuffle] as? Bool else {
                    result(FlutterError(code: "Position error", message: "No URI was specified", details: nil))
                    return
            }
            appRemote.playerAPI?.setShuffle(shuffle, callback: defaultPlayAPICallback)
        case SpotfySdkConstants.methodSetRepeatMode:
            guard let appRemote = appRemote else {
                result(FlutterError(code: "Connection Error", message: "AppRemote is null", details: nil))
                return
            }
            guard let swiftArguments = call.arguments as? [String:Any],
                let repeatModeIndex = swiftArguments[SpotfySdkConstants.paramRepeatMode] as? UInt,
                let repeatMode = SPTAppRemotePlaybackOptionsRepeatMode(rawValue: repeatModeIndex)else {
                    result(FlutterError(code: "Position error", message: "No URI was specified", details: nil))
                    return
            }
            appRemote.playerAPI?.setRepeatMode(repeatMode, callback: defaultPlayAPICallback)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func connectToSpotify(clientId: String, redirectURL: String, accessToken: String? = nil, scope: [String] = []) throws {
        enum SpotifyError: Error {
            case spotifyNotInstalledError
            case spotifyMissingRedirectURLError
        }

        guard let redirectURL = URL(string: redirectURL) else {
            throw SpotifyError.spotifyMissingRedirectURLError
        }
        let configuration = SPTConfiguration(clientID: clientId, redirectURL: redirectURL)
        let appRemote = SPTAppRemote(configuration: configuration, logLevel: .none)
        appRemote.delegate = connectionStatusHandler
        let playerDelegate = PlayerDelegate()
        playerStateHandler = PlayerStateHandler(appRemote: appRemote, playerDelegate: playerDelegate)
        SwiftSpotifySdkPlugin.playerStateChannel?.setStreamHandler(playerStateHandler)

        playerContextHandler = PlayerContextHandler(appRemote: appRemote, playerDelegate: playerDelegate)
        SwiftSpotifySdkPlugin.playerContextChannel?.setStreamHandler(playerContextHandler)

        self.appRemote = appRemote

        // Note: A blank string will play the user's last song or pick a random one.
        if self.appRemote?.authorizeAndPlayURI("", asRadio: false, additionalScopes: scope) != true {
            throw SpotifyError.spotifyNotInstalledError
        }
    }
}

extension SwiftSpotifySdkPlugin {
    public func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        setAccessTokenFromURL(url: url)
        return true
    }

    public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]) -> Void) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
            let url = userActivity.webpageURL
            else {
                connectionStatusHandler?.connectionResult?(FlutterError(code: "errorConnecting", message: "client id or redirectUrl are not set or have invalid format", details: nil))
                connectionStatusHandler?.tokenResult?(FlutterError(code: "errorConnecting", message: "client id or redirectUrl are not set or have invalid format", details: nil))
                connectionStatusHandler?.connectionResult = nil
                connectionStatusHandler?.tokenResult = nil
                return false
        }

        setAccessTokenFromURL(url: url)
        return true
    }

    private func setAccessTokenFromURL(url: URL) {
        guard let appRemote = appRemote else {
            connectionStatusHandler?.connectionResult?(FlutterError(code: "errorConnection", message: "AppRemote is null", details: nil))
            connectionStatusHandler?.tokenResult?(FlutterError(code: "errorConnection", message: "AppRemote is null", details: nil))
            connectionStatusHandler?.connectionResult = nil
            connectionStatusHandler?.tokenResult = nil
            return
        }

        guard let token = appRemote.authorizationParameters(from: url)?[SPTAppRemoteAccessTokenKey] else {
            connectionStatusHandler?.connectionResult?(FlutterError(code: "authenticationTokenError", message: appRemote.authorizationParameters(from: url)?[SPTAppRemoteErrorDescriptionKey], details: nil))
            connectionStatusHandler?.tokenResult?(FlutterError(code: "authenticationTokenError", message: appRemote.authorizationParameters(from: url)?[SPTAppRemoteErrorDescriptionKey], details: nil))
            connectionStatusHandler?.connectionResult = nil
            connectionStatusHandler?.tokenResult = nil
            return
        }

        appRemote.connectionParameters.accessToken = token
        appRemote.connect()
    }
}
