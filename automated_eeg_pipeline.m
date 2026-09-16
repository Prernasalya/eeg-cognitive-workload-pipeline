% Prompt user to select Baseline EDF
[file_base, path_base] = uigetfile('*.edf', 'Select Baseline EEG File (e.g. Subject00_1.edf)');
if isequal(file_base, 0), error('User cancelled baseline file selection.'); end
full_path_base = fullfile(path_base, file_base);

% Prompt user to select Task EDF
[file_task, path_task] = uigetfile('*.edf', 'Select Task EEG File (e.g. Subject00_2.edf)');
if isequal(file_task, 0), error('User cancelled task file selection.'); end
full_path_task = fullfile(path_task, file_task);

% Ensure EEGLAB and its plugin paths are active in memory
if ~exist('pop_biosig', 'file') || ~exist('sopen', 'file')
    [ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab('nogui');
end

% Loading the baseline data in EEGLAB
EEG = pop_biosig(full_path_base);

% Map standard channel locations (using Cap385 / BESA lookup)
EEG = pop_chanedit(EEG, 'lookup', 'standard-10-5-cap385.sfp');

% Filtering the baseline data
EEG = pop_eegfilt( EEG, 0.5, 45, [], [0], 1, 0, 'fir1', 0);

% Epoching the baseline data 
EEG = eeg_regepochs(EEG, 'recurrence', 2, 'limits', [0 2], 'rmbase', NaN);

% Baseline Subtraction
EEG = pop_rmbase(EEG, []);

% Automated Artifact rejection 
EEG = pop_eegthresh(EEG, 1, 1:EEG.nbchan, -80, 80, EEG.xmin, EEG.xmax, 0, 1);

% Dimensions: channels x frames x epochs
[nChan, nFrames, nEpochs] = size(EEG.data);
fs = EEG.srate; % 500 Hz

% Frequency resolution and axis
freqs = (0:(nFrames/2)) * (fs / nFrames);

% Compute two-sided FFT, convert to single-sided power
fft_data = fft(EEG.data, [], 2);
psd_all = (abs(fft_data(:, 1:length(freqs), :)).^2) / (nFrames * fs);
psd_mean = mean(psd_all, 3); % Average across clean epochs

% Define physiological frequency band indices
idx_delta = (freqs >= 1 & freqs < 4);
idx_theta = (freqs >= 4 & freqs < 8);
idx_alpha = (freqs >= 8 & freqs < 13);
idx_beta  = (freqs >= 13 & freqs <= 30);
idx_total = (freqs >= 1 & freqs <= 30);

% Integrate absolute power (Area Under the Curve via trapz)
df = freqs(2) - freqs(1);
pow_theta = trapz(psd_mean(:, idx_theta), 2) * df;
pow_alpha = trapz(psd_mean(:, idx_alpha), 2) * df;
pow_beta  = trapz(psd_mean(:, idx_beta), 2) * df;
pow_total = trapz(psd_mean(:, idx_total), 2) * df;

% Compute relative power
rel_theta = pow_theta ./ pow_total;
rel_alpha = pow_alpha ./ pow_total;
rel_beta  = pow_beta  ./ pow_total;
psd_base = psd_mean;
freqs_base = freqs;

% List channel labels to verify exact row index
{EEG.chanlocs.labels}'

% Compute Theta-to-Beta Ratio (TBR) at frontal midline (Fz)
% Replace 'chan_Fz' with the row number of Fz from your montage
chan_Fz = find(strcmpi({EEG.chanlocs.labels}, 'Fz'));
TBR_baseline = pow_theta(chan_Fz) / pow_beta(chan_Fz);

% Compute Frontal Alpha Asymmetry (FAA) between F4 (right) and F3 (left)
chan_F3 = find(strcmpi({EEG.chanlocs.labels}, 'F3'));
chan_F4 = find(strcmpi({EEG.chanlocs.labels}, 'F4'));
FAA_baseline = log(pow_alpha(chan_F4)) - log(pow_alpha(chan_F3));

fprintf('--- Baseline Metrics (Subject00_1) ---\n');
fprintf('Frontal Midline (Fz) TBR: %.4f\n', TBR_baseline);
fprintf('Frontal Alpha Asymmetry (F4-F3): %.4f\n', FAA_baseline);

% ==========================================
% 2. PROCESS TASK DATA
% ==========================================
EEG = pop_biosig(full_path_task);
EEG = pop_chanedit(EEG, 'lookup', 'standard-10-5-cap385.sfp');
EEG = pop_eegfilt(EEG, 0.5, 45, [], [0], 1, 0, 'fir1', 0);
EEG = eeg_regepochs(EEG, 'recurrence', 2, 'limits', [0 2], 'rmbase', NaN);
EEG = pop_rmbase(EEG, []);
EEG = pop_eegthresh(EEG, 1, 1:EEG.nbchan, -80, 80, EEG.xmin, EEG.xmax, 0, 1);

% Compute Task PSD via FFT
[nChan, nFrames, nEpochs] = size(EEG.data);
fft_data = fft(EEG.data, [], 2);
psd_all = (abs(fft_data(:, 1:length(freqs), :)).^2) / (nFrames * fs);
psd_task = mean(psd_all, 3);

% Integrate band power for Task
pow_theta_task = trapz(psd_task(:, idx_theta), 2) * df;
pow_alpha_task = trapz(psd_task(:, idx_alpha), 2) * df;
pow_beta_task  = trapz(psd_task(:, idx_beta), 2) * df;

% Compute Task Biomarkers
TBR_task = pow_theta_task(chan_Fz) / pow_beta_task(chan_Fz);
FAA_task = log(pow_alpha_task(chan_F4)) - log(pow_alpha_task(chan_F3));

% ==========================================
% 3. STATISTICAL CONTRAST & RESULTS TABLE
% ==========================================
delta_TBR = TBR_task - TBR_baseline;
delta_FAA = FAA_task - FAA_baseline;

fprintf('\n================ COGNITIVE WORKLOAD SUMMARY ================\n');
fprintf('Biomarker                  | Baseline   | Task       | Delta (Task - Base)\n');
fprintf('------------------------------------------------------------\n');
fprintf('Frontal Midline TBR (Fz)   | %10.4f | %10.4f | %+10.4f\n', TBR_baseline, TBR_task, delta_TBR);
fprintf('Frontal Alpha Asymmetry    | %10.4f | %10.4f | %+10.4f\n', FAA_baseline, FAA_task, delta_FAA);
fprintf('============================================================\n');

% ==========================================
% 4. AUTOMATED COMPARATIVE OVERLAY PLOT
% ==========================================
figure('Color', 'w', 'Name', 'Frontal Midline PSD Overlay');
plot(freqs_base, 10*log10(psd_base(chan_Fz, :)), 'b', 'LineWidth', 1.5); hold on;
plot(freqs_base, 10*log10(psd_task(chan_Fz, :)), 'r', 'LineWidth', 1.5);
xlim([1 30]); grid on;
xlabel('Frequency (Hz)');
ylabel('Power Spectral Density (dB/Hz)');
title('Frontal Midline (Fz): Baseline vs. Mental Arithmetic');
legend('Baseline (Rest)', 'Mental Arithmetic (Task)', 'Location', 'northeast');

% Optional: Auto-save the figure
saveas(gcf, 'psd_comparison_Fz.png');