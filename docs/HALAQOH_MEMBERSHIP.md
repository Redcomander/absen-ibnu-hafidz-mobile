# Mobile halaqoh membership requests

Open Halaqoh, find your own group, and select **Ajukan perubahan santri**. Remove students from the proposed list or search by at least two characters to add students. Review the addition/removal counts and confirm submission. Existing membership stays unchanged until approval in the web administration interface.

The screen uses the existing backend routes:

- GET /halaqoh/assignments, without offline cache, for the complete current roster.
- GET /halaqoh/student-options, with debounced search and 20 results per page. Does not use the privileged master student endpoint.
- GET /halaqoh/assignment-change-requests, filtered to the current teacher in the client; the backend also restricts request visibility.
- PUT /halaqoh/assignments/:teacher_id, with the full selected student IDs, the same user ID, and the original helper teacher ID. For regular teachers this creates an approval request, not a live roster update.

Only the original teacher can use this request flow. Helper/substitute visibility does not confer membership management rights. Admin roles continue managing membership on the web; their backend write routes apply changes directly and therefore are deliberately not exposed as teacher approval requests here.

A pending request locks the editor. Request history folds and shows status and admin reasons. The client rechecks pending requests and current membership before sending to avoid replacing a roster changed while the form was open. The backend retains its ownership checks, transaction locks, one-pending-request rule, and approval conflict checks.

This feature requires internet access. Membership writes are never placed into the attendance offline queue. Failed/ambiguous submissions preserve the local form; any retry checks server request status first. Reloading explicitly discards the draft. No student master records are deleted; an approved removal changes group membership. No database migration or backend changes are required when the web membership API is already deployed.

Validation covers owner permissions, combined additions/removals and helper preservation, pending locking/history, and offline failure. Build 5 includes the Android feature.
