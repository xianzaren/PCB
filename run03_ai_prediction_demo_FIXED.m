%% run03_ai_prediction_demo_FIXED.m
% Runs multiple AI risk prediction examples and prints engineering recommendations.
%
% This script demonstrates:
% 1. Normal condition
% 2. Quality risk condition
% 3. Maintenance risk condition
% 4. Combined high-risk condition

clear; clc; close all;

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

%% Load trained models
modelFile = fullfile(outDir, 'trained_risk_models_FIXED.mat');

if ~isfile(modelFile)
    error('Trained models not found. Run train02_ai_risk_models_FIXED.m first.');
end

load(modelFile, 'qualityModel', 'maintenanceModel', 'predictorNames');

%% Multiple example machine/process conditions
% These cases are designed to show that the model can respond differently
% under different process and machine conditions.

testCases = table( ...
    [8; 25; 8; 25], ...           % MeanTempError
    [15; 40; 15; 38], ...         % MaxTempError
    [5; 16; 5; 15], ...           % TempFluctuation
    [55; 65; 88; 88], ...         % AvgHeaterPower
    [0.85; 0.85; 0.85; 0.82], ... % AvgConveyorSpeed
    [2.8; 2.8; 3.2; 3.2], ...     % PeakMotorCurrent
    [0.18; 0.18; 0.24; 0.24], ... % RMSVibration
    [502; 502; 512; 512], ...     % OperatingHours
    'VariableNames', predictorNames);

caseNames = [
    "Normal operation"
    "Quality risk condition"
    "Maintenance risk condition"
    "Combined high-risk condition"
];

%% Predict risk for each case

numCases = height(testCases);

qualityPred = strings(numCases, 1);
maintenancePred = strings(numCases, 1);

riskScores = zeros(numCases, 2);

fprintf('\n=== AI Risk Prediction Demo ===\n');

for i = 1:numCases

    currentCase = testCases(i, :);

    qualityRisk = predict(qualityModel, currentCase);
    maintenanceRisk = predict(maintenanceModel, currentCase);

    qualityRisk = string(qualityRisk);
    maintenanceRisk = string(maintenanceRisk);

    qualityPred(i) = qualityRisk;
    maintenancePred(i) = maintenanceRisk;

    riskScores(i, 1) = riskToNumber(qualityRisk);
    riskScores(i, 2) = riskToNumber(maintenanceRisk);

    fprintf('\n============================================================\n');
    fprintf('Case %d: %s\n', i, caseNames(i));
    fprintf('============================================================\n\n');

    disp('Input condition:');
    disp(currentCase);

    fprintf('Predicted PCB Quality Risk: %s\n', qualityRisk);
    fprintf('Predicted Machine Maintenance Risk: %s\n', maintenanceRisk);

    printDiagnosticCauses(currentCase);

    printRecommendedActions(qualityRisk, maintenanceRisk);
end

%% Save prediction summary table

resultTable = testCases;
resultTable.CaseName = caseNames;
resultTable.PredictedQualityRisk = categorical(qualityPred);
resultTable.PredictedMaintenanceRisk = categorical(maintenancePred);

% Move CaseName to the first column
resultTable = movevars(resultTable, 'CaseName', 'Before', 1);

writetable(resultTable, fullfile(outDir, 'ai_risk_prediction_summary_FIXED.csv'));

disp(' ');
disp('=== Summary Table ===');
disp(resultTable);

%% Create risk result plot for all cases

fig = figure('Name', 'AI Risk Prediction Result for Multiple Conditions');

bar(categorical(caseNames), riskScores);

ylim([0 3]);
ylabel('Risk Level: 1 = Low, 2 = Medium, 3 = High');
title('AI Risk Prediction Result for Multiple Conditions');
legend({'Quality Risk', 'Maintenance Risk'}, 'Location', 'best');
grid on;

saveas(fig, fullfile(outDir, 'ai_risk_prediction_result_FIXED.png'));

%% Local helper function: risk label to number

function n = riskToNumber(riskLabel)

    switch string(riskLabel)
        case "Low"
            n = 1;
        case "Medium"
            n = 2;
        case "High"
            n = 3;
        otherwise
            n = 0;
    end
end

%% Local helper function: print possible diagnostic causes

function printDiagnosticCauses(newCondition)

    fprintf('\nPossible Diagnostic Causes:\n');

    hasCause = false;

    % Temperature-related diagnosis
    if newCondition.MaxTempError > 35
        fprintf('- Large maximum temperature error: the oven temperature may be far from the target reflow profile.\n');
        hasCause = true;

    elseif newCondition.MeanTempError > 20
        fprintf('- High average temperature error: the temperature control may be unstable.\n');
        hasCause = true;
    end

    if newCondition.TempFluctuation > 15
        fprintf('- High temperature fluctuation: possible unstable heating or sensor disturbance.\n');
        hasCause = true;
    end

    % Conveyor-related diagnosis
    if abs(newCondition.AvgConveyorSpeed - 0.85) > 0.05
        fprintf('- Abnormal conveyor speed: PCB heating time may be too short or too long.\n');
        hasCause = true;
    end

    % Heater-related diagnosis
    if newCondition.AvgHeaterPower > 85
        fprintf('- High heater power: possible heater ageing or high thermal load.\n');
        hasCause = true;
    end

    % Motor and vibration diagnosis
    if newCondition.PeakMotorCurrent > 3.15
        fprintf('- High motor current: possible conveyor, fan, or motor load problem.\n');
        hasCause = true;
    end

    if newCondition.RMSVibration > 0.23
        fprintf('- High vibration: possible bearing wear, fan imbalance, or mechanical looseness.\n');
        hasCause = true;
    end

    % Ageing diagnosis
    if newCondition.OperatingHours > 508
        fprintf('- High operating hours: equipment ageing may increase maintenance risk.\n');
        hasCause = true;
    end

    if ~hasCause
        fprintf('- No major abnormal sensor pattern detected in this example condition.\n');
    end
end

%% Local helper function: print maintenance and quality recommendations

function printRecommendedActions(qualityRisk, maintenanceRisk)

    fprintf('\nRecommended Actions:\n');

    if string(qualityRisk) == "High"
        fprintf('- Quality risk is HIGH: inspect sample PCBs and check the reflow temperature profile.\n');

    elseif string(qualityRisk) == "Medium"
        fprintf('- Quality risk is MEDIUM: monitor the next batch and check temperature deviation.\n');

    else
        fprintf('- Quality risk is LOW: continue normal production.\n');
    end

    if string(maintenanceRisk) == "High"
        fprintf('- Maintenance risk is HIGH: schedule inspection of heater, fan, motor or conveyor system.\n');

    elseif string(maintenanceRisk) == "Medium"
        fprintf('- Maintenance risk is MEDIUM: monitor vibration and motor current trends.\n');

    else
        fprintf('- Maintenance risk is LOW: no immediate maintenance action is needed.\n');
    end
end