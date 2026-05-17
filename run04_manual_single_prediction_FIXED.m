%% run04_manual_single_prediction_FIXED.m
% Manually enter one new machine/process condition.
% The trained AI models will return:
% 1. PCB Quality Risk
% 2. Machine Maintenance Risk
% 3. Binary High / Low warning
% 4. Possible diagnostic causes
% 5. Recommended actions

clear; clc; close all;

%% Path setup
projectRoot = fileparts(mfilename('fullpath'));

if isempty(projectRoot)
    projectRoot = pwd;
end

cd(projectRoot);
outDir = fullfile(projectRoot, 'outputs');

%% Load trained models
modelFile = fullfile(outDir, 'trained_risk_models_FIXED.mat');

if ~isfile(modelFile)
    error('Trained models not found. Run train02_ai_risk_models_FIXED.m first.');
end

load(modelFile, 'qualityModel', 'maintenanceModel', 'predictorNames');

% Try to load selected model names if they exist
modelInfo = load(modelFile);

if isfield(modelInfo, 'qualityModelName')
    qualityModelName = string(modelInfo.qualityModelName);
else
    qualityModelName = "Selected quality model";
end

if isfield(modelInfo, 'maintenanceModelName')
    maintenanceModelName = string(modelInfo.maintenanceModelName);
else
    maintenanceModelName = "Selected maintenance model";
end

fprintf('\n=== Manual AI Risk Prediction ===\n');
fprintf('Quality model: %s\n', qualityModelName);
fprintf('Maintenance model: %s\n\n', maintenanceModelName);

fprintf('Please enter one new machine/process condition.\n');
fprintf('Press Enter to use the default value shown in brackets.\n\n');

%% Manual input
% Default values are moderate example values.
% You can change them during command window input.

defaultValues = containers.Map( ...
    {'MeanTempError', 'MaxTempError', 'TempFluctuation', 'AvgHeaterPower', ...
     'AvgConveyorSpeed', 'PeakMotorCurrent', 'RMSVibration', 'OperatingHours'}, ...
    {10.0, 22.0, 6.0, 70.0, 0.86, 3.05, 0.21, 560.0});

inputValues = zeros(1, numel(predictorNames));

for i = 1:numel(predictorNames)
    featureName = predictorNames{i};

    if isKey(defaultValues, featureName)
        defaultValue = defaultValues(featureName);
    else
        defaultValue = 0;
    end

    inputValues(i) = askNumber(featureName, defaultValue);
end

newRow = array2table(inputValues, 'VariableNames', predictorNames);

%% Predict risk
qualityRisk = string(predict(qualityModel, newRow));
maintenanceRisk = string(predict(maintenanceModel, newRow));

qualityBinary = riskToBinary(qualityRisk);
maintenanceBinary = riskToBinary(maintenanceRisk);

%% Display results
fprintf('\n=== New Single Row Prediction Result ===\n\n');

disp('New input row:');
disp(newRow);

fprintf('Predicted PCB Quality Risk: %s\n', qualityRisk);
fprintf('Predicted Machine Maintenance Risk: %s\n', maintenanceRisk);

fprintf('Binary PCB Quality Warning: %s\n', qualityBinary);
fprintf('Binary Machine Maintenance Warning: %s\n', maintenanceBinary);

printDiagnosticCauses(newRow);
printRecommendedActions(qualityRisk, maintenanceRisk);

%% Save result
resultTable = newRow;
resultTable.PredictedQualityRisk = categorical(qualityRisk, ["Low", "Medium", "High"]);
resultTable.PredictedMaintenanceRisk = categorical(maintenanceRisk, ["Low", "Medium", "High"]);
resultTable.BinaryQualityWarning = string(qualityBinary);
resultTable.BinaryMaintenanceWarning = string(maintenanceBinary);

resultFile = fullfile(outDir, 'manual_single_prediction_FIXED.csv');
writetable(resultTable, resultFile);

fprintf('\nSaved manual prediction result to:\n%s\n', resultFile);

%% Local function: ask user input
function value = askNumber(featureName, defaultValue)

    prompt = sprintf('%s [default %.3f]: ', featureName, defaultValue);
    userInput = input(prompt, 's');

    if isempty(strtrim(userInput))
        value = defaultValue;
        return;
    end

    value = str2double(userInput);

    if isnan(value)
        warning('Invalid input for %s. Default value %.3f is used.', featureName, defaultValue);
        value = defaultValue;
    end
end

%% Local function: convert three-class risk to binary warning
function binaryRisk = riskToBinary(riskLabel)

    riskLabel = string(riskLabel);

    % Conservative setting:
    % Medium and High are both treated as High warning.
    if riskLabel == "High" || riskLabel == "Medium"
        binaryRisk = "High";
    else
        binaryRisk = "Low";
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