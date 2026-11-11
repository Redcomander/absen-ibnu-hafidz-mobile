# Imunify360 and mobile API login

The Android client uses https://ibnuhafidz.ponpes.id/api. Browser JavaScript challenges cannot be completed by native API requests, including background synchronization.

Send the hosting provider this request:

> Legitimate Android API requests to https://ibnuhafidz.ponpes.id/api/ are denied by Imunify360 bot protection. Please inspect the matching incident and configure an exception from browser CAPTCHA/JavaScript challenges for the API if supported. Keep application authentication, rate limits, and other WAF protections active. If your deployment supports only domain exceptions, please advise on a dedicated API subdomain and configure its proxy and TLS before we switch clients. Mobile IP addresses change, so a single client IP exception is not a permanent solution.

CloudLinux documents a domain-level CAPTCHA/SplashScreen exception, requiring server administrator access:
https://cloudlinux.zendesk.com/hc/en-us/articles/360017069879-How-to-disable-WebShield-for-a-domain

This exception is broader than an API path: the hosting administrator must select the appropriate scope. Do not disable protection server-wide or expose the local Go port publicly. Do not copy browser clearance cookies into the app or spoof browser identity.

The client classifies explicitly identified Imunify360 challenge responses separately from application permission denials. It keeps remembered sessions, does not refresh tokens because of a challenge, and leaves durable submissions pending for a later retry. Genuine application authorization errors retain their existing behavior. Fresh login still requires a successful backend response; the client cannot remove a hosting block.

After hosting changes, verify the maintenance endpoint returns JSON and unauthenticated auth/me returns a JSON authentication error, then test login and background sync on a phone using Wi-Fi and mobile data. Do not clear app data: it can contain unsent attendance.
