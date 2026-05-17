%% run03_ai_prediction_demo_FIXED.m
% Runs AI risk prediction examples and prints diagnostic causes and recommendations.
%
% This script demonstrates:
% 1. Normal operation
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

load(modelFile, ...
    'qualityModel', ...
    'maintenanceModel', ...
    'predictorNames', ...
    'qualityModelName', ...
    'maintenanceModelName');

fprintf('\n=== AI Risk Prediction Demo ===\n');
fprintf('Selected Quality Risk model: %s\n', string(qualityModelName));
fprintf('Selected Maintenance Risk model: %s\n', string(maintenanceModelName));

%% Load dataset and select representative demo cases
dataFile = fullfile(outDir, 'sensor_features_with_labels_FIXED.mat');

if isfile(dataFile)
    load(dataFile, 'T');
    [testCases, caseNames, expectedQuality, expectedMaintenance] = ...
        selectRepresentativeCases(T, predictorNames);
else
    warning('Dataset not found. Using manual demo cases.');

    caseNames = [
        "Normal operation"
        "Quality risk condition"
        "Maintenance risk condition"
        "Combined high-risk condition"
    ];

    testCases = array2table([
        2.0,   5.0,  1.2, 45.0, 0.85, 2.85, 0.17, 520.0;
        14.0, 30.0, 9.0,  60.0, 0.98, 2.90, 0.18, 525.0;
        3.0,   7.0, 1.5, 88.0, 0.85, 3.45, 0.32, 605.0;
        14.0, 30.0, 9.0,  90.0, 0.74, 3.55, 0.35, 610.0
    ], 'VariableNames', predictorNames);

    expectedQuality = ["Low"; "High"; "Low"; "High"];
    expectedMaintenance = ["Low"; "Low"; "High"; "High"];
end

%% Predict risk for each case
numCases = height(testCases);

qualityPred = strings(numCases, 1);
maintenancePred = strings(numCases, 1);
riskScores = zeros(numCases, 2);

for i = 1:numCases

    currentCase = testCases(i, :);

    qualityRisk = string(predict(qualityModel, currentCase));
    maintenanceRisk = string(predict(maintenanceModel, currentCase));

    qualityPred(i) = qualityRisk;
    maintenancePred(i) = maintenanceRisk;

    riskScores(i, 1) = riskToNumber(qualityRisk);
    riskScores(i, 2) = riskToNumber(maintenanceRisk);

    fprintf('\n============================================================\n');
    fprintf('Case %d: %s\n', i, caseNames(i));
    fprintf('============================================================\n\n');

    disp('Input condition:');
    disp(currentCase);

    fprintf('Expected PCB Quality Risk from generated dataset: %s\n', expectedQuality(i));
    fprintf('Expected Machine Maintenance Risk from generated dataset: %s\n', expectedMaintenance(i));

    fprintf('Predicted PCB Quality Risk: %s\n', qualityRisk);
    fprintf('Predicted Machine Maintenance Risk: %s\n', maintenanceRisk);

    fprintf('Quality Risk Score: %d / 3\n', riskToNumber(qualityRisk));
    fprintf('Maintenance Risk Score: %d / 3\n', riskToNumber(maintenanceRisk));

    fprintf('Quality Warning Lamp: %s\n', riskToLamp(qualityRisk));
    fprintf('Maintenance Warning Lamp: %s\n', riskToLamp(maintenanceRisk));

    printDiagnosticCauses(currentCase);
    printRecommendedActions(qualityRisk, maintenanceRisk);
end

%% Save prediction summary table
resultTable = testCases;
resultTable.CaseName = caseNames;
resultTable.ExpectedQualityRisk = categorical(expectedQuality, ["Low", "Medium", "High"]);
resultTable.ExpectedMaintenanceRisk = categorical(expectedMaintenance, ["Low", "Medium", "High"]);
resultTable.PredictedQualityRisk = categorical(qualityPred, ["Low", "Medium", "High"]);
resultTable.PredictedMaintenanceRisk = categorical(maintenancePred, ["Low", "Medium", "High"]);

resultTable.QualityRiskScore = riskScores(:, 1);
resultTable.MaintenanceRiskScore = riskScores(:, 2);

resultTable.QualityWarningLamp = arrayfun(@riskToLamp, qualityPred);
resultTable.MaintenanceWarningLamp = arrayfun(@riskToLamp, maintenancePred);

resultTable = movevars(resultTable, 'CaseName', 'Before', 1);

writetable(resultTable, fullfile(outDir, 'ai_risk_prediction_summary_FIXED.csv'));

disp(' ');
disp('=== Summary Table ===');
disp(resultTable);

%% Create risk result plot for all cases
fig = figure('Name', 'AI Risk Prediction Result for Multiple Conditions');

caseCats = categorical(caseNames);
caseCats = reordercats(caseCats, cellstr(caseNames));

bar(caseCats, riskScores);

ylim([0 3]);
ylabel('Risk Level: 1 = Low, 2 = Medium, 3 = High');
title('AI Risk Prediction Result for Multiple Conditions');
legend({'Quality Risk', 'Maintenance Risk'}, 'Location', 'best');
grid on;

saveas(fig, fullfile(outDir, 'ai_risk_prediction_result_FIXED.png'));

disp(' ');
disp('Saved demo prediction outputs:');
disp(fullfile(outDir, 'ai_risk_prediction_summary_FIXED.csv'));
disp(fullfile(outDir, 'ai_risk_prediction_result_FIXED.png'));

%% Local function: select representative demo cases
function [testCases, caseNames, expectedQuality, expectedMaintenance] = ...
    selectRepresentativeCases(T, predictorNames)

    caseNames = [
        "Normal operation"
        "Quality risk condition"
        "Maintenance risk condition"
        "Combined high-risk condition"
    ];

    % Target risk pairs:
    % Low-Low, High-Low, Low-High, High-High
    targetPairs = [
        1 1
        3 1
        1 3
        3 3
    ];

    qNum = arrayfun(@(x) riskToNumber(x), string(T.QualityRisk));
    mNum = arrayfun(@(x) riskToNumber(x), string(T.MaintenanceRisk));

    selectedIdx = zeros(4, 1);
    used = false(height(T), 1);

    for i = 1:4
        targetQ = targetPairs(i, 1);
        targetM = targetPairs(i, 2);

        distance = (qNum - targetQ).^2 + (mNum - targetM).^2;
        distance(used) = inf;

        [~, idx] = min(distance);

        selectedIdx(i) = idx;
        used(idx) = true;
    end

    testCases = T(selectedIdx, predictorNames);
    expectedQuality = string(T.QualityRisk(selectedIdx));
    expectedMaintenance = string(T.MaintenanceRisk(selectedIdx));
end

%% Local function: risk label to number
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

%% Local function: risk label to warning lamp
function lamp = riskToLamp(riskLabel)

    switch string(riskLabel)
        case "Low"
            lamp = "Green";
        case "Medium"
            lamp = "Amber";
        case "High"
            lamp = "Red";
        otherwise
            lamp = "Grey";
    end
end

%% Local function: print possible diagnostic causes
function printDiagnosticCauses(newCondition)

    fprintf('\nPossible Diagnostic Causes:\n');

    hasCause = false;

    if newCondition.MaxTempError > 25
        fprintf('- Large maximum temperature error: the oven temperature may be far from the target reflow profile.\n');
        hasCause = true;

    elseif newCondition.MeanTempError > 12
        fprintf('- High average temperature error: the temperature control may be unstable.\n');
        hasCause = true;
    end

    if newCondition.TempFluctuation > 8
        fprintf('- High temperature fluctuation: possible unstable heating or sensor disturbance.\n');
        hasCause = true;
    end

    if abs(newCondition.AvgConveyorSpeed - 0.85) > 0.04
        fprintf('- Abnormal conveyor speed: PCB heating time may be too short or too long.\n');
        hasCause = true;
    end

    if newCondition.AvgHeaterPower > 75
        fprintf('- High heater power: possible heater ageing or high thermal load.\n');
        hasCause = true;
    end

    if newCondition.PeakMotorCurrent > 3.15
        fprintf('- High motor current: possible conveyor, fan, or motor load problem.\n');
        hasCause = true;
    end

    if newCondition.RMSVibration > 0.23
        fprintf('- High vibration: possible bearing wear, fan imbalance, or mechanical looseness.\n');
        hasCause = true;
    end

    if newCondition.OperatingHours > 580 && ...
       (newCondition.RMSVibration > 0.20 || ...
        newCondition.PeakMotorCurrent > 3.00 || ...
        newCondition.AvgHeaterPower > 70)

        fprintf('- High operating hours combined with abnormal signals: equipment ageing may increase maintenance risk.\n');
        hasCause = true;
    end

    if ~hasCause
        fprintf('- No major abnormal sensor pattern detected in this example condition.\n');
    end
end

%% Local function: print recommendations
function printRecommendedActions(qualityRisk, maintenanceRisk)

    fprintf('\nRecommended Actions:\n');

    if qualityRisk == "High"
        fprintf('- Quality risk is HIGH: inspect sample PCBs and check the reflow temperature profile.\n');

    elseif qualityRisk == "Medium"
        fprintf('- Quality risk is MEDIUM: monitor the next batch and check temperature deviation.\n');

    else
        fprintf('- Quality risk is LOW: continue normal production.\n');
    end

    if maintenanceRisk == "High"
        fprintf('- Maintenance risk is HIGH: schedule inspection of heater, fan, motor or conveyor system.\n');

    elseif maintenanceRisk == "Medium"
        fprintf('- Maintenance risk is MEDIUM: monitor vibration and motor current trends.\n');

    else
        fprintf('- Maintenance risk is LOW: no immediate maintenance action is needed.\n');
    end
end