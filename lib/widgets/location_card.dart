import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/location_model.dart';

class LocationCard extends StatelessWidget {
  final LocationData location;
  final int index;
  final int total;
  final VoidCallback? onRefresh;
  final VoidCallback? onDelete;
  final bool isSelected;
  final VoidCallback? onSelectionChanged;
  
  const LocationCard({
    Key? key,
    required this.location,
    required this.index,
    required this.total,
    this.onRefresh,
    this.onDelete,
    this.isSelected = false,
    this.onSelectionChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('MMM dd, yyyy').format(location.timestamp);
    final formattedTime = DateFormat('hh:mm:ss a').format(location.timestamp);
    
    // Determine sync status and colors
    final bool isSynced = location.isSynced;
    final Color statusColor = isSynced 
        ? Colors.green 
        : (location.errorMessage != null ? Colors.red : Colors.orange);
    final Color borderColor = isSynced 
        ? Colors.green.shade200 
        : (location.errorMessage != null ? Colors.red.shade200 : Colors.orange.shade200);
    
    // Selection mode visual enhancements
    final Color cardColor = isSelected ? Colors.blue.withOpacity(0.1) : Colors.white;
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? Colors.blue : borderColor,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onSelectionChanged != null 
            ? onSelectionChanged 
            : onRefresh,
        onLongPress: onSelectionChanged != null && !isSelected
            ? onSelectionChanged
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Location index with selection indicator
                  Row(
                    children: [
                      if (onSelectionChanged != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onSelectionChanged,
                              borderRadius: BorderRadius.circular(24),
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Icon(
                                  isSelected 
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: isSelected ? Colors.blue : Colors.grey,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '#${total - index}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Actions row
                  Row(
                    children: [
                      // Sync status indicator
                      _buildSyncStatus(context, statusColor),
                      
                      // Show delete button unless in selection mode
                      if (onDelete != null) 
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: ElevatedButton.icon(
                            onPressed: onDelete,
                            icon: const Icon(Icons.delete, size: 16),
                            label: const Text('Delete'),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.red,
                              elevation: 2,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: const Size(80, 30),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 16),
              // Coordinates section
              Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.blue, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Coordinates',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: _buildCoordinateItem(
                                context, 
                                'Lat', 
                                location.latitude.toStringAsFixed(6),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildCoordinateItem(
                                context, 
                                'Long', 
                                location.longitude.toStringAsFixed(6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Timestamp section
              Row(
                children: [
                  const Icon(Icons.access_time, color: Colors.deepPurple, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Timestamp',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: _buildDetailItem(context, 'Date', formattedDate),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildDetailItem(context, 'Time', formattedTime),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              // Show retry button or error message if needed
              if (location.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Error: ${location.errorMessage}',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
                            onPressed: onRefresh,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Retry'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildSyncStatus(BuildContext context, Color statusColor) {
    // Determine status icon and text
    IconData statusIcon;
    String statusText;
    
    if (location.isSynced) {
      statusIcon = Icons.cloud_done;
      statusText = 'Synced';
    } else if (location.errorMessage != null) {
      statusIcon = Icons.error_outline;
      statusText = 'Error';
    } else if (location.retryCount > 0) {
      statusIcon = Icons.replay_circle_filled;
      statusText = 'Retrying (${location.retryCount})';
    } else {
      statusIcon = Icons.cloud_upload;
      statusText = 'Pending';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3))
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            statusIcon,
            color: statusColor,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordinateItem(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(BuildContext context, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
} 