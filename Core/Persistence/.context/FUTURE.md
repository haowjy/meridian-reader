# Persistence: deferred

- **Save's move under an older key is outside the audio journal.** When an older page holds the
  address under another key than the reader's, `ArticleSaveCoordinator.save` moves the reader's
  audio under the page's key (`migrateListenCache`) and rekeys the live session after the save
  is stored. If the app dies between the two, that audio stays under the reader's key, ephemeral:
  the page doesn't get it back (opening it adopts only v1 keys, `ReaderArticle.legacyCacheKeys`),
  so it is rendered again, and the age prune takes the old copy. Journaling it needs a record that
  can move audio under a live player; the `merge` record reconciles files and isn't safe for that.
