import { StatusBar } from 'expo-status-bar';
import {
  StyleSheet,
  Text,
  View,
  ScrollView,
  TouchableOpacity,
  ActivityIndicator,
  TextInput,
  SafeAreaView,
} from 'react-native';
import { useEffect, useState, useCallback } from 'react';
import {
  getSystemInfo,
  ASRManager,
  StreamingASRManager,
  VADManager,
  DiarizationManager,
  TTSManager,
  onModelLoadProgress,
  cleanup,
} from '@fluidinference/react-native-fluidaudio';

export default function App() {
  const [systemInfo, setSystemInfo] = useState(null);
  const [loading, setLoading] = useState(false);
  const [loadingStatus, setLoadingStatus] = useState('');
  const [result, setResult] = useState('');
  const [ttsText, setTtsText] = useState('Hello from FluidAudio!');

  // Streaming state
  const [isStreaming, setIsStreaming] = useState(false);
  const [streamingText, setStreamingText] = useState('');
  const [confirmedText, setConfirmedText] = useState('');

  // Manager instances
  const [asr] = useState(() => new ASRManager());
  const [streaming] = useState(() => new StreamingASRManager());
  const [vad] = useState(() => new VADManager());
  const [diarizer] = useState(() => new DiarizationManager());
  const [tts] = useState(() => new TTSManager());

  // Initialization states
  const [asrReady, setAsrReady] = useState(false);
  const [vadReady, setVadReady] = useState(false);
  const [diarizationReady, setDiarizationReady] = useState(false);
  const [ttsReady, setTtsReady] = useState(false);

  useEffect(() => {
    getSystemInfo().then(setSystemInfo).catch(err => {
      setResult(`Error getting system info: ${err.message}`);
    });

    const subscription = onModelLoadProgress((event) => {
      setLoadingStatus(`${event.type ?? 'Model'}: ${event.status} (${event.progress}%)`);
    });

    return () => {
      subscription.remove();
      cleanup();
    };
  }, []);

  // Streaming ASR
  const handleStreamingUpdate = useCallback((update) => {
    setStreamingText(update.volatile);
    setConfirmedText(update.confirmed);
  }, []);

  const startStreaming = useCallback(async () => {
    setLoading(true);
    setResult('');
    setStreamingText('');
    setConfirmedText('');
    try {
      await streaming.start({ source: 'microphone' }, handleStreamingUpdate);
      setIsStreaming(true);
      setResult('Streaming started - speak into the microphone!');
    } catch (error) {
      setResult(`Error: ${error.message}`);
    } finally {
      setLoading(false);
    }
  }, [streaming, handleStreamingUpdate]);

  const stopStreaming = useCallback(async () => {
    setLoading(true);
    try {
      const stopResult = await streaming.stop();
      setIsStreaming(false);
      setResult(`Final transcription:\n${stopResult.text || '(no speech detected)'}`);
      setStreamingText('');
      setConfirmedText('');
    } catch (error) {
      setResult(`Error: ${error.message}`);
    } finally {
      setLoading(false);
    }
  }, [streaming]);

  // ASR
  const initializeASR = useCallback(async () => {
    setLoading(true);
    setResult('');
    try {
      const initResult = await asr.initialize();
      setAsrReady(true);
      setResult(`ASR initialized in ${initResult.compilationDuration.toFixed(2)}s\nReady for transcription!`);
    } catch (error) {
      setResult(`Error: ${error.message}`);
    } finally {
      setLoading(false);
      setLoadingStatus('');
    }
  }, [asr]);

  // VAD
  const initializeVAD = useCallback(async () => {
    setLoading(true);
    setResult('');
    try {
      await vad.initialize({ threshold: 0.85 });
      setVadReady(true);
      setResult('VAD initialized successfully\nReady for voice activity detection!');
    } catch (error) {
      setResult(`Error: ${error.message}`);
    } finally {
      setLoading(false);
    }
  }, [vad]);

  // Diarization
  const initializeDiarization = useCallback(async () => {
    setLoading(true);
    setResult('');
    try {
      const initResult = await diarizer.initialize({
        clusteringThreshold: 0.7,
        numClusters: -1,
      });
      setDiarizationReady(true);
      setResult(`Diarization initialized in ${initResult.compilationDuration.toFixed(2)}s\nReady for speaker identification!`);
    } catch (error) {
      setResult(`Error: ${error.message}`);
    } finally {
      setLoading(false);
      setLoadingStatus('');
    }
  }, [diarizer]);

  // TTS
  const initializeTTS = useCallback(async () => {
    setLoading(true);
    setResult('');
    try {
      await tts.initialize({ variant: 'fiveSecond' });
      setTtsReady(true);
      setResult('TTS initialized successfully\nReady for speech synthesis!');
    } catch (error) {
      setResult(`Error: ${error.message}`);
    } finally {
      setLoading(false);
      setLoadingStatus('');
    }
  }, [tts]);

  const synthesizeSpeech = useCallback(async () => {
    if (!ttsText.trim()) {
      setResult('Please enter some text to synthesize');
      return;
    }
    setLoading(true);
    try {
      const audio = await tts.synthesize(ttsText);
      setResult(
        `Synthesized "${ttsText}"\nDuration: ${audio.duration.toFixed(2)}s\nSample rate: ${audio.sampleRate}Hz`
      );
    } catch (error) {
      setResult(`Error: ${error.message}`);
    } finally {
      setLoading(false);
    }
  }, [tts, ttsText]);

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView contentContainerStyle={styles.scrollContent}>
        <Text style={styles.title}>FluidAudio Demo</Text>

        {/* System Info */}
        {systemInfo && (
          <View style={styles.infoBox}>
            <Text style={styles.infoTitle}>System Info</Text>
            <Text style={styles.infoText}>
              Platform: {systemInfo.platform}
              {'\n'}Apple Silicon: {systemInfo.isAppleSilicon ? 'Yes' : 'No'}
              {'\n'}{systemInfo.summary}
            </Text>
          </View>
        )}

        {/* Loading Status */}
        {loadingStatus ? (
          <View style={styles.statusBox}>
            <ActivityIndicator size="small" color="#007AFF" />
            <Text style={styles.statusText}>{loadingStatus}</Text>
          </View>
        ) : null}

        {/* Streaming Display */}
        {isStreaming && (
          <View style={styles.streamingBox}>
            <Text style={styles.streamingTitle}>Live Transcription</Text>
            <Text style={styles.confirmedText}>{confirmedText}</Text>
            <Text style={styles.volatileText}>{streamingText}</Text>
          </View>
        )}

        {/* Streaming ASR */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Streaming Speech-to-Text</Text>
          <Text style={styles.sectionDesc}>Real-time transcription from microphone</Text>
          {!isStreaming ? (
            <TouchableOpacity
              style={[styles.button, styles.buttonPrimary, loading && styles.buttonDisabled]}
              onPress={startStreaming}
              disabled={loading}
            >
              <Text style={styles.buttonText}>🎤 Start Streaming</Text>
            </TouchableOpacity>
          ) : (
            <TouchableOpacity
              style={[styles.button, styles.buttonDanger]}
              onPress={stopStreaming}
            >
              <Text style={styles.buttonText}>⏹ Stop Streaming</Text>
            </TouchableOpacity>
          )}
        </View>

        {/* ASR */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Speech-to-Text (ASR)</Text>
          <Text style={styles.sectionDesc}>Initialize model for file transcription</Text>
          <TouchableOpacity
            style={[
              styles.button,
              asrReady ? styles.buttonSuccess : styles.buttonSecondary,
              loading && styles.buttonDisabled,
            ]}
            onPress={initializeASR}
            disabled={loading || asrReady}
          >
            <Text style={styles.buttonText}>
              {asrReady ? '✓ ASR Ready' : 'Initialize ASR'}
            </Text>
          </TouchableOpacity>
        </View>

        {/* VAD */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Voice Activity Detection</Text>
          <Text style={styles.sectionDesc}>Detect speech segments in audio</Text>
          <TouchableOpacity
            style={[
              styles.button,
              vadReady ? styles.buttonSuccess : styles.buttonSecondary,
              loading && styles.buttonDisabled,
            ]}
            onPress={initializeVAD}
            disabled={loading || vadReady}
          >
            <Text style={styles.buttonText}>
              {vadReady ? '✓ VAD Ready' : 'Initialize VAD'}
            </Text>
          </TouchableOpacity>
        </View>

        {/* Diarization */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Speaker Diarization</Text>
          <Text style={styles.sectionDesc}>Identify different speakers in audio</Text>
          <TouchableOpacity
            style={[
              styles.button,
              diarizationReady ? styles.buttonSuccess : styles.buttonSecondary,
              loading && styles.buttonDisabled,
            ]}
            onPress={initializeDiarization}
            disabled={loading || diarizationReady}
          >
            <Text style={styles.buttonText}>
              {diarizationReady ? '✓ Diarization Ready' : 'Initialize Diarization'}
            </Text>
          </TouchableOpacity>
        </View>

        {/* TTS */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Text-to-Speech</Text>
          <Text style={styles.sectionDesc}>Convert text to natural speech</Text>
          <TouchableOpacity
            style={[
              styles.button,
              ttsReady ? styles.buttonSuccess : styles.buttonSecondary,
              loading && styles.buttonDisabled,
            ]}
            onPress={initializeTTS}
            disabled={loading || ttsReady}
          >
            <Text style={styles.buttonText}>
              {ttsReady ? '✓ TTS Ready' : 'Initialize TTS'}
            </Text>
          </TouchableOpacity>

          {ttsReady && (
            <View style={styles.ttsInputContainer}>
              <TextInput
                style={styles.ttsInput}
                value={ttsText}
                onChangeText={setTtsText}
                placeholder="Enter text to speak..."
                multiline
              />
              <TouchableOpacity
                style={[styles.button, styles.buttonPrimary, loading && styles.buttonDisabled]}
                onPress={synthesizeSpeech}
                disabled={loading}
              >
                <Text style={styles.buttonText}>🔊 Synthesize</Text>
              </TouchableOpacity>
            </View>
          )}
        </View>

        {/* Result */}
        {result ? (
          <View style={styles.resultBox}>
            <Text style={styles.resultTitle}>Result</Text>
            <Text style={styles.resultText}>{result}</Text>
          </View>
        ) : null}

        {loading && !loadingStatus && (
          <ActivityIndicator size="large" color="#007AFF" style={styles.loader} />
        )}

        <StatusBar style="auto" />
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  scrollContent: {
    padding: 20,
    paddingBottom: 40,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: 20,
    color: '#333',
  },
  infoBox: {
    backgroundColor: '#e3f2fd',
    padding: 15,
    borderRadius: 10,
    marginBottom: 20,
  },
  infoTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
    color: '#1565c0',
  },
  infoText: {
    fontSize: 14,
    color: '#333',
    lineHeight: 20,
  },
  statusBox: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#fff3e0',
    padding: 12,
    borderRadius: 8,
    marginBottom: 15,
  },
  statusText: {
    marginLeft: 10,
    fontSize: 14,
    color: '#e65100',
  },
  streamingBox: {
    backgroundColor: '#1a1a2e',
    padding: 15,
    borderRadius: 10,
    marginBottom: 20,
  },
  streamingTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: '#4fc3f7',
    marginBottom: 10,
  },
  confirmedText: {
    fontSize: 16,
    color: '#ffffff',
    lineHeight: 24,
  },
  volatileText: {
    fontSize: 16,
    color: '#81d4fa',
    fontStyle: 'italic',
    lineHeight: 24,
  },
  section: {
    marginBottom: 24,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 4,
    color: '#333',
  },
  sectionDesc: {
    fontSize: 13,
    color: '#666',
    marginBottom: 10,
  },
  button: {
    paddingVertical: 14,
    paddingHorizontal: 20,
    borderRadius: 10,
    marginBottom: 10,
  },
  buttonPrimary: {
    backgroundColor: '#007AFF',
  },
  buttonSecondary: {
    backgroundColor: '#5856D6',
  },
  buttonSuccess: {
    backgroundColor: '#34C759',
  },
  buttonDanger: {
    backgroundColor: '#FF3B30',
  },
  buttonDisabled: {
    backgroundColor: '#ccc',
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
    textAlign: 'center',
  },
  ttsInputContainer: {
    marginTop: 10,
  },
  ttsInput: {
    backgroundColor: '#fff',
    borderRadius: 10,
    padding: 12,
    fontSize: 16,
    borderWidth: 1,
    borderColor: '#ddd',
    marginBottom: 10,
    minHeight: 60,
  },
  resultBox: {
    backgroundColor: '#e8f5e9',
    padding: 15,
    borderRadius: 10,
    marginTop: 10,
  },
  resultTitle: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 8,
    color: '#2e7d32',
  },
  resultText: {
    fontSize: 14,
    color: '#333',
    lineHeight: 20,
  },
  loader: {
    marginTop: 20,
  },
});
