import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether this device currently has a live connection to Firebase.
///
/// Read from `.info/connected`, a node the Realtime Database SDK maintains
/// itself. It reflects the actual socket to Firebase, which is the thing that
/// matters for calling. A plain "is Wi-Fi on" check would say yes on a
/// captive portal or a network with no internet.
///
/// This matters more than it looks: the RTDB SDK does not fail writes while
/// offline, it queues them and completes the future only once reconnected.
/// A call placed without this check would therefore hang silently instead of
/// telling the user they are offline.
///
/// `null` (loading) means "not known yet" and should not block the user.
final firebaseConnectedProvider = StreamProvider<bool>((ref) {
  return FirebaseDatabase.instance
      .ref('.info/connected')
      .onValue
      .map((event) => event.snapshot.value == true);
});
