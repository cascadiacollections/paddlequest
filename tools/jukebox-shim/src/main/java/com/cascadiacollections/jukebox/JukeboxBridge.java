package com.cascadiacollections.jukebox;

import android.util.Log;
import android.webkit.ConsoleMessage;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/**
 * The parts of the jukebox panel that GDScript cannot reach.
 *
 * <p>Not here for convenience. Since Android P the WebView implementation lives in its own
 * classloader, and the object behind the abstract {@link WebSettings} is
 * com.android.webview.chromium.ContentSettingsAdapter, which the app classloader cannot see.
 * JavaClassWrapper wraps a return value by its concrete class, so {@code getSettings()} never
 * becomes callable from GDScript and JavaScript can never be turned on.
 *
 * <p>The way out is that the object never has to cross the boundary. JavaClassWrapper only
 * chokes on <em>returning</em> something unwrappable; passing in a WebView is fine, because
 * android.webkit.WebView is a framework class the app classloader does see. So every method
 * here takes the WebView and returns void, and the unwrappable settings object stays in Java.
 *
 * <p>{@link WebViewClient} and {@link WebChromeClient} are the same story for a different
 * reason: they are classes with many methods rather than single-method interfaces, so
 * JavaClassWrapper.create_sam_callback cannot implement them from a Callable.
 *
 * <p>Arguments are primitives and strings only. The host list arrives as one comma-separated
 * string rather than an array, because string arrays are the marshalling case least worth
 * betting a device round-trip on.
 */
public final class JukeboxBridge {
	private static final String TAG = "Jukebox";

	private JukeboxBridge() {}

	/**
	 * Applies the settings the panel needs. Call on the UI thread, before loading anything.
	 *
	 * @param autoplay  whether media may start without a user gesture - a jukebox has no
	 *                  cursor to tap with, so it must
	 * @param userAgent sent instead of the WebView default when non-empty. The default is a
	 *                  mobile UA, which sends youtube.com to m.youtube.com and from there to
	 *                  an intent:// deep link the Presentation context cannot launch.
	 */
	public static void configure(WebView view, boolean autoplay, String userAgent) {
		WebSettings settings = view.getSettings();
		settings.setJavaScriptEnabled(true);
		settings.setDomStorageEnabled(true);
		settings.setMediaPlaybackRequiresUserGesture(!autoplay);

		// The allowlist stops us navigating to file:// ourselves; these stop the page
		// reaching for it behind our back, and are the layer the README says is missing
		// whenever this shim is not in the build.
		settings.setAllowFileAccess(false);
		settings.setAllowContentAccess(false);
		settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);

		if (userAgent != null && !userAgent.isEmpty()) {
			settings.setUserAgentString(userAgent);
		}

		Log.i(TAG, "settings applied: javascript=on autoplay=" + autoplay);
	}

	/**
	 * Installs the navigation policy and the console//error logging.
	 *
	 * <p>The allowlist is enforced here rather than only at load_url(), because a link the
	 * page itself follows never passes through GDScript at all.
	 *
	 * @param allowedHostsCsv comma-separated hosts; empty means nothing is allowed
	 */
	public static void installClients(WebView view, String allowedHostsCsv) {
		final String[] hosts = splitHosts(allowedHostsCsv);
		view.setWebViewClient(new AllowlistClient(hosts));
		view.setWebChromeClient(new LoggingChromeClient());
		Log.i(TAG, "clients installed: " + hosts.length + " allowed host(s)");
	}

	/**
	 * Loads {@code html} as a document belonging to {@code baseUrl}.
	 *
	 * <p>Here because YouTube's embed player answers a top-level request with "Error 153" -
	 * no Referer, no embedding origin, no player. It has to run in an iframe inside a page
	 * that has an origin of its own, which is also the embedding route YouTube's terms
	 * describe. loadUrl() cannot express that and loadData() has no origin to give; only
	 * loadDataWithBaseURL() does, and its historyUrl argument is a null String that is not
	 * worth trying to pass through JavaClassWrapper.
	 */
	public static void loadEmbed(WebView view, String baseUrl, String html) {
		view.loadDataWithBaseURL(baseUrl, html, "text/html", "utf-8", null);
		Log.i(TAG, "loaded embed document with base " + baseUrl);
	}

	static String[] splitHosts(String csv) {
		if (csv == null || csv.trim().isEmpty()) {
			return new String[0];
		}
		String[] parts = csv.split(",");
		for (int i = 0; i < parts.length; i++) {
			parts[i] = parts[i].trim().toLowerCase();
		}
		return parts;
	}

	/**
	 * Whether the panel may navigate here. Mirrors Jukebox.is_allowed() in GDScript: https
	 * only, suffix match on a dot boundary so "youtube.com" covers "music.youtube.com" but
	 * not "notyoutube.com".
	 */
	static boolean isAllowed(String url, String[] hosts) {
		if (url == null) {
			return false;
		}
		String trimmed = url.trim().toLowerCase();
		if (!trimmed.startsWith("https://")) {
			return false;
		}

		String host = hostOf(trimmed);
		if (host.isEmpty()) {
			return false;
		}

		for (String allowed : hosts) {
			if (!allowed.isEmpty() && (host.equals(allowed) || host.endsWith("." + allowed))) {
				return true;
			}
		}
		return false;
	}

	/** The host of a URL: no scheme, credentials, port or path. "" when it cannot be read. */
	static String hostOf(String url) {
		String rest = url;
		int scheme = rest.indexOf("://");
		if (scheme != -1) {
			rest = rest.substring(scheme + 3);
		}

		for (String separator : new String[] {"/", "?", "#"}) {
			int at = rest.indexOf(separator);
			if (at != -1) {
				rest = rest.substring(0, at);
			}
		}

		// user:pass@host - taking the first '@' would let "youtube.com@evil.example" read
		// as YouTube.
		int credentials = rest.lastIndexOf('@');
		if (credentials != -1) {
			rest = rest.substring(credentials + 1);
		}

		if (rest.startsWith("[")) { // [::1]:8080 - the colons inside are not a port.
			int close = rest.indexOf(']');
			return close != -1 ? rest.substring(0, close + 1) : "";
		}

		int port = rest.lastIndexOf(':');
		if (port != -1) {
			rest = rest.substring(0, port);
		}
		return rest;
	}

	private static final class AllowlistClient extends WebViewClient {
		private final String[] hosts;

		AllowlistClient(String[] hosts) {
			this.hosts = hosts;
		}

		@Override
		public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
			String url = request.getUrl().toString();
			if (isAllowed(url, hosts)) {
				return false;
			}
			// Covers intent:// too, which is what youtube.com reaches for when it wants to
			// hand off to the installed app - a Presentation has no Activity to launch it.
			Log.w(TAG, "blocked navigation to " + url);
			return true;
		}

		@Override
		public void onPageFinished(WebView view, String url) {
			Log.i(TAG, "page finished: " + url);
		}

		@Override
		public void onReceivedError(
				WebView view, WebResourceRequest request, WebResourceError error) {
			if (request.isForMainFrame()) {
				Log.e(TAG, "page error " + error.getErrorCode() + ": " + error.getDescription());
			}
		}
	}

	/**
	 * Present for two reasons: HTML5 video wants a chrome client to be fully happy, and the
	 * page's own console is the only window into what the panel is doing. Everything here is
	 * read through logcat, since the panel cannot be inspected any other way.
	 */
	private static final class LoggingChromeClient extends WebChromeClient {
		@Override
		public boolean onConsoleMessage(ConsoleMessage message) {
			Log.i(TAG, "console: " + message.message() + " @" + message.lineNumber());
			return true;
		}
	}
}
