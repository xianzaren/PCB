%% generate01_sensor_data_from_simulink_FIXED.m
% Runs the Simulink model, extracts signals, creates features and synthetic labels.

clear; clc; close all;
rng(42);   % fixed random seed for reproducibility

%% Path setup
projectRoot = fileparts(mfilename('fullpath'));
if isempty(projectRoot)
    projectRoot = pwd;
end
cd(projectRoot);
outDir = fullfile(projectRoot, 'outputs');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

%% Model setup
model = 'SmartPCB_Reflow_AI_Model_FIXED';
modelFile = fullfile(projectRoot, [model '.slx']);
if ~isfile(modelFile)
    error('Model file not found. Run create00_reflow_oven_simulink_model_FIXED.m first.');
end

inputFile = fullfile(outDir, 'simulink_input_timeseries.mat');
if ~isfile(inputFile)
    error('Input timeseries file not found. Run create00_reflow_oven_simulink_model_FIXED.m first.');
end

%% Load input timeseries for From Workspace blocks
load(inputFile, 'reflow_setpoint_ts', 'conveyor_speed_ts', 'motor_current_ts', ...
    'vibration_ts', 'operating_hours_ts');
assignin('base', 'reflow_setpoint_ts', reflow_setpoint_ts);
assignin('base', 'conveyor_speed_ts', conveyor_speed_ts);
assignin('base', 'motor_current_ts', motor_current_ts);
assignin('base', 'vibration_ts', vibration_ts);
assignin('base', 'operating_hours_ts', operating_hours_ts);

%% Run simulation
load_system(modelFile);
out = sim(model, 'StopTime', get_param(model, 'StopTime'));

%% Read simulation output variables
setpoint_temperature = out.setpoint_temperature;
actual_temperature = out.actual_temperature;
temperature_error = out.temperature_error;
heater_power = out.heater_power;
conveyor_speed = out.conveyor_speed;
motor_current = out.motor_current;
vibration = out.vibration;
operating_hours = out.operating_hours;

%% Extract values
t = actual_temperature.time(:);
setp = setpoint_temperature.signals.values(:);
temp = actual_temperature.signals.values(:);
err  = temperature_error.signals.values(:);
hp   = heater_power.signals.values(:);
spd  = conveyor_speed.signals.values(:);
cur  = motor_current.signals.values(:);
vib  = vibration.signals.values(:);
hrs  = operating_hours.signals.values(:);

n = min([numel(t), numel(setp), numel(temp), numel(err), numel(hp), ...
    numel(spd), numel(cur), numel(vib), numel(hrs)]);
t=t(1:n); setp=setp(1:n); temp=temp(1:n); err=err(1:n); hp=hp(1:n);
spd=spd(1:n); cur=cur(1:n); vib=vib(1:n); hrs=hrs(1:n);

%% Window-level feature extraction
windowSize = 10;
stepSize = 2;          % overlapping sliding window, increases dataset size
features = [];

for i = 1:stepSize:(n-windowSize+1)
    idx = i:(i+windowSize-1);

    features = [features; ...
        mean(abs(err(idx))), ...
        max(abs(err(idx))), ...
        std(temp(idx)), ...
        mean(hp(idx)), ...
        mean(spd(idx)), ...
        max(cur(idx)), ...
        sqrt(mean(vib(idx).^2)), ...
        mean(hrs(idx))]; %#ok<AGROW>
end

T = array2table(features, 'VariableNames', { ...
    'MeanTempError', 'MaxTempError', 'TempFluctuation', 'AvgHeaterPower', ...
    'AvgConveyorSpeed', 'PeakMotorCurrent', 'RMSVibration', 'OperatingHours'});

%% Scenario-based synthetic labels
%% Score-based balanced synthetic labels
% This avoids nearly all samples becoming High after increasing simulation time.
% Quality risk mainly depends on process quality signals.
% Maintenance risk mainly depends on machine health signals.

conveyorDeviation = abs(T.AvgConveyorSpeed - 0.85);

qualityScore = ...
    0.35 * minmax01(T.MeanTempError) + ...
    0.35 * minmax01(T.MaxTempError) + ...
    0.20 * minmax01(T.TempFluctuation) + ...
    0.10 * minmax01(conveyorDeviation);

maintenanceScore = ...
    0.25 * minmax01(T.AvgHeaterPower) + ...
    0.30 * minmax01(T.PeakMotorCurrent) + ...
    0.30 * minmax01(T.RMSVibration) + ...
    0.15 * minmax01(T.OperatingHours);

T.QualityScore = qualityScore;
T.MaintenanceScore = maintenanceScore;

qualityRisk = assignBalancedLabels(qualityScore);
maintenanceRisk = assignBalancedLabels(maintenanceScore);

T.QualityRisk = categorical(qualityRisk, ["Low", "Medium", "High"]);
T.MaintenanceRisk = categorical(maintenanceRisk, ["Low", "Medium", "High"]);

%% Check label distribution
qualityCounts = countcats(T.QualityRisk);
maintenanceCounts = countcats(T.MaintenanceRisk);
riskClasses = categorical(["Low"; "Medium"; "High"], ["Low", "Medium", "High"]);

labelDistribution = table(riskClasses, qualityCounts, maintenanceCounts, ...
    'VariableNames', {'RiskClass', 'QualityRiskCount', 'MaintenanceRiskCount'});

disp('Label distribution after balanced assignment:');
disp(labelDistribution);

writetable(labelDistribution, fullfile(outDir, 'label_distribution_FIXED.csv'));

%% Save dataset
writetable(T, fullfile(outDir, 'sensor_features_with_labels_FIXED.csv'));
save(fullfile(outDir, 'sensor_features_with_labels_FIXED.mat'), 'T');

%% Plot 1: Temperature tracking
fig1 = figure('Name', 'Reflow Temperature Tracking');
plot(t, setp, 'LineWidth', 1.5); hold on;
plot(t, temp, 'LineWidth', 1.5);
xlabel('Time (s)'); ylabel('Temperature (C)');
title('Reflow Oven Temperature Tracking');
legend('Target Temperature', 'Actual Temperature', 'Location', 'best');
grid on;
saveas(fig1, fullfile(outDir, 'temperature_tracking_FIXED.png'));

%% Plot 2: Sensor trends
fig2 = figure('Name', 'Sensor Trends');
plot(t, hp, 'LineWidth', 1.2); hold on;
plot(t, cur, 'LineWidth', 1.2);
plot(t, vib*100, 'LineWidth', 1.2);
plot(t, spd*100, 'LineWidth', 1.2);
xlabel('Time (s)'); ylabel('Scaled Value');
title('Simulated Sensor Trends');
legend('Heater Power', 'Motor Current', 'Vibration x100', 'Conveyor Speed x100', 'Location', 'best');
grid on;
saveas(fig2, fullfile(outDir, 'sensor_trends_FIXED.png'));

disp('Generated feature dataset:');
disp(fullfile(outDir, 'sensor_features_with_labels_FIXED.csv'));
disp(T);

%% Local functions

function y = minmax01(x)
x = x(:);
xmin = min(x);
xmax = max(x);

if xmax == xmin
    y = zeros(size(x));
else
    y = (x - xmin) ./ (xmax - xmin);
end
end

function labels = assignBalancedLabels(score)
score = score(:);
n = numel(score);

[~, order] = sort(score, 'ascend');

labels = strings(n, 1);

nLow = floor(n / 3);
nMedium = floor(n / 3);

labels(order(1:nLow)) = "Low";
labels(order(nLow+1:nLow+nMedium)) = "Medium";
labels(order(nLow+nMedium+1:end)) = "High";
end
