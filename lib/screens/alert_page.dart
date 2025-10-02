import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class AlertsPage extends StatefulWidget {
  const AlertsPage({super.key});

  @override
  State<AlertsPage> createState() => _AlertsPageState();
}

class _AlertsPageState extends State<AlertsPage> {
  String? _role;

  @override
  void initState() {
    super.initState();
    _getRole();
  }

  Future<void> _getRole() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          setState(() {
            _role = doc['role'];
          });
        }
      } catch (e) {
        print('Error fetching role: $e');
      }
    }
  }

  void _sendCustomNotification(
    BuildContext context,
    String reportId,
    String hazardType,
    double lat,
    double long,
    DateTime time,
  ) {
    final _msgController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Custom Notification'),
        content: TextField(
          controller: _msgController,
          decoration: const InputDecoration(
            hintText: 'Enter your custom message',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              String message = _msgController.text.trim();
              if (message.isNotEmpty) {
                try {
                  await FirebaseFirestore.instance.collection('notifications').add({
                    'reportId': reportId,
                    'hazardType': hazardType,
                    'latitude': lat,
                    'longitude': long,
                    'timestamp': Timestamp.fromDate(time),
                    'message': message,
                    'sentAt': FieldValue.serverTimestamp(),
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Notification sent: $message')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to send notification: $e')),
                  );
                }
              }
              Navigator.pop(context);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_role == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        backgroundColor: Colors.blue,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('reports')
            .where('status', isEqualTo: 'verified')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          print('Snapshot: connectionState=${snapshot.connectionState}, hasData=${snapshot.hasData}, error=${snapshot.error}');
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error loading alerts: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No verified alerts available.'));
          }

          final docs = snapshot.data!.docs;
          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final String hazardType = data['hazardType'] ?? 'Unknown';
              final double lat = data['latitude'] ?? 0.0;
              final double long = data['longitude'] ?? 0.0;
              final Timestamp? ts = data['timestamp'];
              final DateTime time = ts?.toDate() ?? DateTime.now();
              final String formattedTime = DateFormat('yyyy-MM-dd HH:mm').format(time);

              return Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8.0),
                child: ListTile(
                  title: Text(hazardType, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Location: $lat, $long\nTime: $formattedTime'),
                  trailing: _role == 'admin'
                      ? IconButton(
                          icon: const Icon(Icons.send, color: Colors.blue),
                          tooltip: 'Send Custom Notification',
                          onPressed: () => _sendCustomNotification(
                            context,
                            docs[index].id,
                            hazardType,
                            lat,
                            long,
                            time,
                          ),
                        )
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }
}