import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _blurIntensity = 30.0;
  bool _useMagicEraser = false;
  double _imageQuality = 95.0;
  double _confidenceThreshold = 0.25;
  List<String> _allLabels = [];
  List<String> _selectedLabels = ['person'];
  bool _isLoadingLabels = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadLabels();
  }

  Future<void> _loadLabels() async {
    try {
      final String labelsData = await DefaultAssetBundle.of(context).loadString('assets/models/labels.txt');
      setState(() {
        _allLabels = labelsData.split('\n').where((s) => s.trim().isNotEmpty).toList();
        _isLoadingLabels = false;
      });
    } catch (e) {
      debugPrint('Error loading labels: $e');
      setState(() {
        _isLoadingLabels = false;
      });
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _blurIntensity = (prefs.getDouble('blur_intensity') ?? 30.0).clamp(5.0, 50.0);
      _useMagicEraser = prefs.getBool('use_magic_eraser') ?? false;
      _imageQuality = (prefs.getDouble('image_quality') ?? 95.0).clamp(50.0, 100.0);
      _confidenceThreshold = (prefs.getDouble('confidence_threshold') ?? 0.25).clamp(0.1, 0.9);
      _selectedLabels = prefs.getStringList('selected_labels') ?? ['person'];
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('blur_intensity', _blurIntensity.clamp(5.0, 50.0));
    await prefs.setBool('use_magic_eraser', _useMagicEraser);
    await prefs.setDouble('image_quality', _imageQuality);
    await prefs.setDouble('confidence_threshold', _confidenceThreshold);
    await prefs.setStringList('selected_labels', _selectedLabels);
  }

  void _showModernLabelSelection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 20),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  
                  // Title and Actions
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Select Objects',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedLabels.clear();
                            });
                            _saveSettings();
                            // Force rebuild of sheet content is handled by StatefulBuilder below if we passed state, 
                            // but here we are modifying parent state. 
                            // We need to trigger a rebuild of the modal content.
                            Navigator.pop(context); // Simple way: close and reopen or just let user see effect on next open. 
                            // Better: Use a ValueNotifier or just rely on the fact that we will rebuild the chips below.
                            _showModernLabelSelection(); // Re-open to refresh (hacky but effective for "Clear All")
                          },
                          child: const Text('Clear All', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  ),
                  
                  const Divider(color: Colors.grey),
                  
                  // Content
                  Expanded(
                    child: _isLoadingLabels 
                      ? const Center(child: CircularProgressIndicator())
                      : StatefulBuilder(
                      builder: (context, setModalState) {
                        return ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(20),
                          children: [
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _allLabels.map((label) {
                                final isSelected = _selectedLabels.contains(label);
                                return FilterChip(
                                  label: Text(label),
                                  selected: isSelected,
                                  onSelected: (bool selected) {
                                    setState(() {
                                      if (selected) {
                                        _selectedLabels.add(label);
                                      } else {
                                        _selectedLabels.remove(label);
                                      }
                                    });
                                    _saveSettings();
                                    setModalState(() {}); // Update the modal UI
                                  },
                                  backgroundColor: Colors.grey[800],
                                  selectedColor: Colors.amber,
                                  checkmarkColor: Colors.black,
                                  labelStyle: TextStyle(
                                    color: isSelected ? Colors.black : Colors.white,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: BorderSide(
                                      color: isSelected ? Colors.amber : Colors.grey[700]!,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  
                  // Bottom Action
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Effect Type', 
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          SwitchListTile(
            title: const Text('Magic Eraser (Remove Person)', 
              style: TextStyle(color: Colors.white)),
            subtitle: const Text('Fill with background color instead of blur',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
            value: _useMagicEraser,
            activeColor: Colors.amber,
            onChanged: (value) {
              setState(() {
                _useMagicEraser = value;
              });
              _saveSettings();
            },
          ),
          const SizedBox(height: 20),
          
          const Text('Blur Intensity', 
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text('Current: ${_blurIntensity.round()}', 
            style: const TextStyle(color: Colors.grey)),
          Slider(
            value: _blurIntensity,
            min: 25,
            max: 150,
            divisions: 45,
            label: _blurIntensity.round().toString(),
            activeColor: Colors.amber,
            onChanged: (value) {
              setState(() {
                _blurIntensity = value;
              });
            },
            onChangeEnd: (value) {
              _saveSettings();
            },
          ),
          const SizedBox(height: 10),
          const Text('Higher values = stronger blur (15-150)',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
            
          const SizedBox(height: 20),
          const Text('Image Quality', 
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text('Current: ${_imageQuality.round()}%', 
            style: const TextStyle(color: Colors.grey)),
          Slider(
            value: _imageQuality,
            min: 50,
            max: 100,
            divisions: 10,
            label: '${_imageQuality.round()}%',
            activeColor: Colors.amber,
            onChanged: (value) {
              setState(() {
                _imageQuality = value;
              });
            },
            onChangeEnd: (value) {
              _saveSettings();
            },
          ),

          const SizedBox(height: 20),
          const Text('AI Confidence', 
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text('Minimum Confidence: ${(_confidenceThreshold * 100).round()}%', 
            style: const TextStyle(color: Colors.grey)),
          Slider(
            value: _confidenceThreshold,
            min: 0.1,
            max: 0.9,
            divisions: 8,
            label: '${(_confidenceThreshold * 100).round()}%',
            activeColor: Colors.amber,
            onChanged: (value) {
              setState(() {
                _confidenceThreshold = value;
              });
            },
            onChangeEnd: (value) {
              _saveSettings();
            },
          ),
          const SizedBox(height: 10),
          const Text('Lower = more detections (may include errors)\nHigher = fewer detections (only sure matches)',
            style: TextStyle(color: Colors.grey, fontSize: 12)),

          const SizedBox(height: 20),
          const Text('Detection', 
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ListTile(
            title: const Text('Selected Objects', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _selectedLabels.isEmpty ? 'None' : _selectedLabels.join(', '),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
            onTap: _showModernLabelSelection,
          ),
        ],
      ),
    );
  }
}
