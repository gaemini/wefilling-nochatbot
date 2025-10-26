# Push Notification Test Scenarios

## Preconditions
- App installed and FCM permission granted
- At least two test users: A (author/host), B (recipient)
- B is logged-in on a real device (preferred) or simulator with push enabled
- In Notification Settings:
  - All Notifications: ON
  - Turn ON only the scenario-specific toggles

---

## 1) Private Post (post_private)
- User A creates a post with visibility = category
- Ensure `allowedUserIds` includes B and excludes A
- Expected:
  - B receives a push: title: "A · <post title>", body: post preview
  - A does not receive any push
  - If B turns off Private Post toggle → no push

## 2) Comment (new_comment)
- User A creates a post (any visibility)
- User B comments on that post
- Expected:
  - A receives a push: "B commented on your post"
  - If A turns off Comment toggle → no push
  - If B comments on own post → no push

## 3) Like (new_like)
- User A creates a post
- User B taps Like
- Expected:
  - A receives a push: "B liked your post"
  - Unliking then liking again should send again only if list grows
  - If A turns off Like toggle → no push

## 4) Meetup Full (meetup_full)
- User A hosts meetup with Max Participants = 2 (host counts as 1)
- User B joins → participant count hits 2
- Expected:
  - A receives a push: "Meetup is full"
  - If A turns off Meetup Full toggle → no push

## 5) Meetup Cancelled (meetup_cancelled)
- User A creates a meetup and invites B (B in participants)
- A deletes the meetup (or a cancellation action that removes the doc)
- Expected:
  - B receives a push: "Meetup cancelled"
  - If B turns off Meetup Cancelled toggle → no push

## 6) Friend Request (friend_request)
- User A sends friend request to B
- Expected:
  - B receives a push: "New friend request"
  - If B turns off Friend Request toggle → no push

## 7) Ad Updates (ad_updates)
- Turn ON "Ad Updates" and ensure app subscribed to topic `ads`
- Create/update a doc in `ad_banners` with title/subtitle
- Expected:
  - All users who turned ON ad_updates receive push
  - Users with ad_updates OFF do not receive push

---

## Troubleshooting Checklist
- Verify user document has `fcmToken`
- Check `user_settings.notifications` keys
- Cloud Functions logs: onPrivatePostCreated, onCommentCreated, onPostLiked, onMeetupUpdated, onMeetupDeleted, onAdBannerChanged
- iOS: allow notifications in system settings
- Android: channel `high_importance_channel` exists


