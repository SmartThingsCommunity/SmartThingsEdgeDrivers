# Samsung-Audio integration documentation

The purpose of this readme is to document the behavior of various samsung lan speaker devices,
since during the development of the driver there have been some weird behavior.
The document will also explain any mitigations the driver makes to provide a
consistent integration despite the weird behavior.

## Device testing notes

Audio Speaker Device shows some weird behavior while responding to various commands. Due to non uniform response by devices, device state mismatch can be
observed sometimes in the ST app.

## Samsung Audio TTS Notification

Currently, Audio TTS notification is played with certain non expected behaviors. For example, when the speakers are in paused state, the notification plays but the queued music resumes playing. Similarly, when speakers are in mute state, it will unmute and play the notification but the speakers will remain unmuted after this. 
