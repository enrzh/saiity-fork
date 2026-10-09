# sAiity privacy policy

Last updated: October 9, 2026. This repository document describes the current app; the published website and App Store privacy answers require separate review before release.

## Voice and network use

Speech recognition runs on your iPhone with installed Whisper, Parakeet or Qwen models. Local cleanup uses Apple Intelligence or an installed local model. Qwen and local MLX processing require the foreground app on compatible hardware. Core dictation does not require an account or a speech server.

Installing models contacts their hosting service, including Hugging Face and its download infrastructure. Preparing Apple translation or Intelligence resources can also require downloads. These requests expose ordinary connection information to the hosting service; they do not upload your recording for speech recognition.

Ollama cleanup is optional. If you explicitly select a configured Ollama model, the app sends the dictated text, cleanup instructions and configured vocabulary to that endpoint. The endpoint may be another device on your network or a hosted server. Its operator controls its handling of that data. Choose a server you trust, or choose on-device cleanup to keep this processing on your iPhone.

## Keyboard permissions and clipboard

Full Access lets the keyboard communicate with the containing app through shared storage and supports optional keyboard features. It is separate from microphone permission. The containing app captures audio; the keyboard sends start/stop requests and inserts the result. Turning keyboard dictation on prepares availability and does not start recording by itself.

Typing, correction and cursor movement use the host field's available text context. The app stores explicit vocabulary and approved learned words, rather than a continuous keystroke history. Sensitive host-field policies disable learning and correction where applicable. The Paste action reads clipboard text when you choose it. Clipboard availability checks can show whether Paste is available.

## Local data and your controls

- Preferences, installed models, vocabulary and shortcuts are stored locally in the app or shared App Group container.
- Dictation history is enabled by default and bounded. Saved entries can include original and processed text. Turning saving off stops new entries and preserves previously saved history until you delete it.
- Pending delivery and the latest in-memory result support recovery. Even with history off, a result waiting for insertion can remain in shared storage until it is delivered, canceled or replaced.
- Optional replay is off by default. It keeps up to the last 60 seconds of audio in memory for at most five minutes, until the next dictation or until you leave the app. Replay audio is not saved or shared by this feature.
- Technical diagnostics are local. Transcript-bearing cleanup diagnostics require explicit consent and history enabled. New cleanup events have a seven-day retention window; older legacy diagnostic files remain until Clear. Turning transcript collection off redacts diagnostic reads/exports and stops storing text in new events; it does not erase previously consented records. Cleanup diagnostics → Clear removes both current and legacy records and reports storage failures.
- Copy, Share, support reports and diagnostic exports are your actions. Data you choose to share is handled by the destination you select. Exported files can remain in the system temporary/share storage.

The app does not include an advertising or tracking workflow. Required-reason API declarations describe local preferences, file operations and elapsed timing; they are not permission to send this data elsewhere. This source document does not assert an App Store privacy label has been reviewed or accepted by Apple.

## Support and attribution

Use [sAiity support](https://github.com/enrzh/saiity-fork/issues) for questions. Support issues may be public; include only information you intend to share. The separate MIT license and third-party notices retain attribution to Dictus and its contributors.

---

# Confidentialité de sAiity

Mise à jour : 9 octobre 2026. La reconnaissance vocale s'effectue sur votre iPhone avec des modèles installés. Leur installation contacte les services d'hébergement. Les modèles locaux ne nécessitent pas de serveur vocal ni de compte. Qwen et le traitement MLX nécessitent une app au premier plan et un appareil compatible.

Si vous choisissez explicitement un modèle de nettoyage Ollama, le texte dicté, les instructions et le vocabulaire configuré sont envoyés au serveur choisi. Son exploitant détermine le traitement de ces données. Choisissez un serveur de confiance ou un nettoyage sur l'appareil.

L'Accès complet permet la communication entre le clavier et l'app ; l'autorisation du microphone est distincte. C'est l'app qui enregistre lorsque vous lancez une dictée. Activer le service ne démarre pas un enregistrement. L'action Coller lit le presse-papiers lorsque vous la choisissez.

Les préférences, modèles, mots et raccourcis restent stockés localement. L'historique est activé par défaut et limité ; le désactiver préserve les entrées déjà enregistrées jusqu'à leur suppression. Un résultat en attente d'insertion reste disponible jusqu'à sa livraison, son annulation ou son remplacement. La réécoute facultative, désactivée par défaut, conserve au maximum 60 secondes en mémoire pendant cinq minutes, jusqu'à la prochaine dictée ou la sortie de l'app.

Les diagnostics contenant des transcriptions nécessitent un consentement explicite et un historique activé. Désactiver cette option masque le texte dans les lectures et exports et empêche de nouveaux enregistrements de texte ; les anciens diagnostics consentis restent locaux jusqu'à Effacer. Les nouveaux événements sont conservés sept jours ; Effacer supprime aussi les anciens fichiers et signale les erreurs. Copier, Partager et exporter sont des actions volontaires ; la destination choisie gère ensuite les données partagées.

Pour les questions, utilisez le lien d'assistance ci-dessus. Les tickets peuvent être publics. La politique publiée sur le site et les réponses de confidentialité App Store doivent être vérifiées séparément avant publication.
