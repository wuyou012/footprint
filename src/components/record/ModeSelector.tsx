import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';

import {
  RECORDING_PROFILES,
  RECORDING_PROFILE_ORDER,
  type RecordingProfile,
} from '../../services/RecordingProfile';

type ModeSelectorProps = {
  value: RecordingProfile;
  onChange: (profile: RecordingProfile) => void;
  disabled?: boolean;
};

/**
 * High / Daily / Eco selection card. Disabled while recording — a mode switch
 * mid-session is intentionally out of F2 scope (would need a new segment).
 */
export function ModeSelector({
  value,
  onChange,
  disabled = false,
}: ModeSelectorProps) {
  return (
    <View style={styles.card}>
      <View style={styles.row}>
        {RECORDING_PROFILE_ORDER.map((profile) => {
          const active = profile === value;
          return (
            <TouchableOpacity
              key={profile}
              disabled={disabled}
              style={[
                styles.chip,
                active && styles.chipActive,
                disabled && !active && styles.chipDisabled,
              ]}
              onPress={() => onChange(profile)}
            >
              <Text style={[styles.chipText, active && styles.chipTextActive]}>
                {RECORDING_PROFILES[profile].label}
              </Text>
            </TouchableOpacity>
          );
        })}
      </View>
      <Text style={styles.description}>{RECORDING_PROFILES[value].description}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    backgroundColor: 'rgba(17, 24, 39, 0.82)',
    borderRadius: 14,
    padding: 12,
    gap: 8,
  },
  row: {
    flexDirection: 'row',
    gap: 8,
  },
  chip: {
    flex: 1,
    paddingVertical: 10,
    borderRadius: 10,
    backgroundColor: 'rgba(255, 255, 255, 0.10)',
    alignItems: 'center',
  },
  chipActive: {
    backgroundColor: '#0F766E',
  },
  chipDisabled: {
    opacity: 0.4,
  },
  chipText: {
    color: '#E5E7EB',
    fontSize: 15,
    fontWeight: '600',
  },
  chipTextActive: {
    color: '#FFFFFF',
  },
  description: {
    color: '#CBD5E1',
    fontSize: 12.5,
    lineHeight: 17,
  },
});
