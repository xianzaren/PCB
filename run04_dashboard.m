function run041_dashboard()
% run041_dashboard.m
% Interactive dashboard for AI risk prediction.
%
% Supports:
% 1. Manual single-row input
% 2. CSV stream input
% 3. Real-time dashboard update
% 4. Warning lamps, risk scores, causes and actions
%
% Run after:
% create00_reflow_oven_simulink_model_FIXED
% generate01_sensor_data_from_simulink_FIXED
% train02_ai_risk_models_FIXED

clc; close all;

%% Path setup
projectRoot = fileparts(mfilename('fullpath'));

if isempty(projectRoot)
    projectRoot = pwd;
end

cd(projectRoot);

outDir = fullfile(projectRoot, 'outputs');
dashboardDir = fullfile(projectRoot, 'dashboard_data');

if ~exist(dashboardDir, 'dir')
    mkdir(dashboardDir);
end

%% Load trained models
modelFile = fullfile(outDir, 'trained_risk_models_FIXED.mat');

if ~isfile(modelFile)
    error('Trained models not found. Run train02_ai_risk_models_FIXED.m first.');
end

modelInfo = load(modelFile);

qualityModel = modelInfo.qualityModel;
maintenanceModel = modelInfo.maintenanceModel;
predictorNames = modelInfo.predictorNames;

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

%% Default values for manual input
defaultValues = containers.Map( ...
    {'MeanTempError', 'MaxTempError', 'TempFluctuation', 'AvgHeaterPower', ...
     'AvgConveyorSpeed', 'PeakMotorCurrent', 'RMSVibration', 'OperatingHours'}, ...
    {10.0, 22.0, 6.0, 70.0, 0.86, 3.05, 0.21, 560.0});

%% History setup
historyTable = table();
historyFile = fullfile(dashboardDir, 'run041_dashboard_prediction_history_FIXED.csv');

csvData = table();
csvIndex = 0;
timerObj = [];

%% Create UI figure
fig = uifigure('Name', 'AI Reflow Monitoring Dashboard', ...
    'Position', [50 50 1500 880]);

fig.CloseRequestFcn = @closeDashboard;

mainGrid = uigridlayout(fig, [4 3]);
mainGrid.RowHeight = {75, 105, '1x', 190};
mainGrid.ColumnWidth = {350, 560, '1x'};
mainGrid.Padding = [15 15 15 15];
mainGrid.RowSpacing = 12;
mainGrid.ColumnSpacing = 12;

%% Title panel
titlePanel = uipanel(mainGrid, 'Title', '');
titlePanel.Layout.Row = 1;
titlePanel.Layout.Column = [1 3];

titleGrid = uigridlayout(titlePanel, [2 1]);
titleGrid.RowHeight = {42, 25};

uilabel(titleGrid, ...
    'Text', 'AI Dashboard: SMT Reflow Quality Prediction and Predictive Maintenance', ...
    'FontSize', 18, ...
    'FontWeight', 'bold');

uilabel(titleGrid, ...
    'Text', sprintf('Selected models: Quality = %s | Maintenance = %s', ...
    qualityModelName, maintenanceModelName), ...
    'FontSize', 12);

%% CSV control panel
controlPanel = uipanel(mainGrid, 'Title', 'CSV Stream Control');
controlPanel.Layout.Row = 2;
controlPanel.Layout.Column = [1 3];

controlGrid = uigridlayout(controlPanel, [2 7]);
controlGrid.RowHeight = {35, 35};
controlGrid.ColumnWidth = {80, '1x', 90, 90, 110, 110, 110};
controlGrid.Padding = [10 8 10 8];

uilabel(controlGrid, 'Text', 'CSV file:');
csvPathField = uieditfield(controlGrid, 'text');

defaultCsv = fullfile(dashboardDir, 'dashboard_50row_holdout_FIXED.csv');

if isfile(defaultCsv)
    csvPathField.Value = defaultCsv;
else
    csvPathField.Value = fullfile(outDir, 'sensor_features_with_labels_FIXED.csv');
end

browseButton = uibutton(controlGrid, ...
    'Text', 'Browse', ...
    'ButtonPushedFcn', @browseCsvFile);

loadCsvButton = uibutton(controlGrid, ...
    'Text', 'Load CSV', ...
    'ButtonPushedFcn', @loadCsvFile);

startButton = uibutton(controlGrid, ...
    'Text', 'Start Stream', ...
    'FontWeight', 'bold', ...
    'ButtonPushedFcn', @startCsvStream);

pauseButton = uibutton(controlGrid, ...
    'Text', 'Pause', ...
    'ButtonPushedFcn', @pauseCsvStream);

stepButton = uibutton(controlGrid, ...
    'Text', 'Step One Row', ...
    'ButtonPushedFcn', @stepCsvOnce);

statusLabel = uilabel(controlGrid, ...
    'Text', 'Status: waiting', ...
    'FontAngle', 'italic');
statusLabel.Layout.Row = 2;
statusLabel.Layout.Column = [1 3];

rowLabel = uilabel(controlGrid, ...
    'Text', 'CSV row: 0 / 0', ...
    'FontWeight', 'bold');
rowLabel.Layout.Row = 2;
rowLabel.Layout.Column = 4;

resetCsvButton = uibutton(controlGrid, ...
    'Text', 'Reset CSV', ...
    'ButtonPushedFcn', @resetCsvStream);
resetCsvButton.Layout.Row = 2;
resetCsvButton.Layout.Column = 5;

clearHistoryButton = uibutton(controlGrid, ...
    'Text', 'Clear History', ...
    'ButtonPushedFcn', @clearHistory);
clearHistoryButton.Layout.Row = 2;
clearHistoryButton.Layout.Column = 6;

saveLabel = uilabel(controlGrid, ...
    'Text', 'Results saved to dashboard_data/', ...
    'FontSize', 11);
saveLabel.Layout.Row = 2;
saveLabel.Layout.Column = 7;

%% Manual input panel
inputPanel = uipanel(mainGrid, 'Title', 'Manual Single-Row Input');
inputPanel.Layout.Row = 3;
inputPanel.Layout.Column = 1;

inputGrid = uigridlayout(inputPanel, [10 2]);
inputGrid.RowHeight = repmat({32}, 1, 10);
inputGrid.ColumnWidth = {170, '1x'};
inputGrid.Padding = [10 10 10 10];

inputFields = gobjects(numel(predictorNames), 1);

for i = 1:numel(predictorNames)
    featureName = predictorNames{i};

    uilabel(inputGrid, ...
        'Text', featureName, ...
        'FontSize', 12);

    if isKey(defaultValues, featureName)
        defaultValue = defaultValues(featureName);
    else
        defaultValue = 0;
    end

    inputFields(i) = uieditfield(inputGrid, 'numeric', ...
        'Value', defaultValue, ...
        'FontSize', 12);
end

predictManualButton = uibutton(inputGrid, ...
    'Text', 'Predict Manual Row', ...
    'FontSize', 14, ...
    'FontWeight', 'bold', ...
    'ButtonPushedFcn', @predictManualRow);
predictManualButton.Layout.Column = [1 2];

resetManualButton = uibutton(inputGrid, ...
    'Text', 'Reset Default Values', ...
    'FontSize', 12, ...
    'ButtonPushedFcn', @resetManualInput);
resetManualButton.Layout.Column = [1 2];

%% Risk result panel
resultPanel = uipanel(mainGrid, 'Title', 'Real-Time Risk Prediction');
resultPanel.Layout.Row = 3;
resultPanel.Layout.Column = 2;

resultGrid = uigridlayout(resultPanel, [6 3]);
resultGrid.RowHeight = {30, 45, 45, 25, 260, 25};
resultGrid.ColumnWidth = {180, 95, '1x'};
resultGrid.Padding = [12 12 12 12];

uilabel(resultGrid, 'Text', 'Prediction', 'FontWeight', 'bold', 'FontSize', 13);
uilabel(resultGrid, 'Text', 'Lamp', 'FontWeight', 'bold', 'FontSize', 13);
uilabel(resultGrid, 'Text', 'Risk score', 'FontWeight', 'bold', 'FontSize', 13);

qualityLabel = uilabel(resultGrid, ...
    'Text', 'PCB Quality Risk: -', ...
    'FontSize', 14, ...
    'FontWeight', 'bold');

qualityLamp = uilamp(resultGrid);
qualityLamp.Color = [0.5 0.5 0.5];

qualityScoreLabel = uilabel(resultGrid, ...
    'Text', '- / 3', ...
    'FontSize', 14);

maintenanceLabel = uilabel(resultGrid, ...
    'Text', 'Maintenance Risk: -', ...
    'FontSize', 14, ...
    'FontWeight', 'bold');

maintenanceLamp = uilamp(resultGrid);
maintenanceLamp.Color = [0.5 0.5 0.5];

maintenanceScoreLabel = uilabel(resultGrid, ...
    'Text', '- / 3', ...
    'FontSize', 14);

currentSourceLabel = uilabel(resultGrid, ...
    'Text', 'Current source: -', ...
    'FontAngle', 'italic', ...
    'FontSize', 12);
currentSourceLabel.Layout.Column = [1 3];

riskAxes = uiaxes(resultGrid);
riskAxes.Layout.Row = 5;
riskAxes.Layout.Column = [1 3];

title(riskAxes, 'Risk Score Trend');
xlabel(riskAxes, 'Prediction step');
ylabel(riskAxes, 'Risk level');
ylim(riskAxes, [0 3]);
yticks(riskAxes, [1 2 3]);
yticklabels(riskAxes, {'Low', 'Medium', 'High'});
grid(riskAxes, 'on');

lastUpdateLabel = uilabel(resultGrid, ...
    'Text', 'Last update: -', ...
    'FontAngle', 'italic', ...
    'FontSize', 11);
lastUpdateLabel.Layout.Column = [1 3];

%% Diagnosis and recommendation panel
textPanel = uipanel(mainGrid, 'Title', 'Diagnosis and Recommendation');
textPanel.Layout.Row = 3;
textPanel.Layout.Column = 3;

textGrid = uigridlayout(textPanel, [5 1]);
textGrid.RowHeight = {25, '1x', 25, '1x', 60};
textGrid.Padding = [10 10 10 10];

uilabel(textGrid, ...
    'Text', 'Possible Diagnostic Causes', ...
    'FontWeight', 'bold', ...
    'FontSize', 13);

diagnosisBox = uitextarea(textGrid, ...
    'Editable', 'off', ...
    'FontSize', 12);

uilabel(textGrid, ...
    'Text', 'Recommended Actions', ...
    'FontWeight', 'bold', ...
    'FontSize', 13);

recommendationBox = uitextarea(textGrid, ...
    'Editable', 'off', ...
    'FontSize', 12);

explainBox = uitextarea(textGrid, ...
    'Editable', 'off', ...
    'FontSize', 11, ...
    'Value', { ...
    'This dashboard supports manual single-row prediction and CSV stream prediction.'; ...
    'CSV streaming simulates real-time sensor-feature input.'; ...
    'The system updates risk, lamp, score, causes and actions immediately.'});

%% History panel
historyPanel = uipanel(mainGrid, 'Title', 'Prediction History');
historyPanel.Layout.Row = 4;
historyPanel.Layout.Column = [1 3];

historyGrid = uigridlayout(historyPanel, [1 1]);
historyGrid.Padding = [8 8 8 8];

historyTableUI = uitable(historyGrid);
historyTableUI.Data = table();

%% Initial prediction
predictManualRow();

%% Callback: browse CSV
    function browseCsvFile(~, ~)
        [file, path] = uigetfile('*.csv', 'Select CSV input file');

        if isequal(file, 0)
            return;
        end

        csvPathField.Value = fullfile(path, file);
    end

%% Callback: load CSV
    function loadCsvFile(~, ~)
        csvPath = strtrim(csvPathField.Value);

        if ~isfile(csvPath)
            uialert(fig, ['CSV file not found: ' csvPath], 'File Error');
            return;
        end

        inputTable = readtable(csvPath);

        missingCols = setdiff(predictorNames, inputTable.Properties.VariableNames);

        if ~isempty(missingCols)
            uialert(fig, ...
                ['CSV is missing required columns: ' strjoin(missingCols, ', ')], ...
                'CSV Column Error');
            return;
        end

        csvData = inputTable;
        csvIndex = 0;

        rowLabel.Text = sprintf('CSV row: 0 / %d', height(csvData));
        statusLabel.Text = sprintf('Status: CSV loaded, %d rows', height(csvData));
    end

%% Callback: start CSV stream
    function startCsvStream(~, ~)
        if isempty(csvData)
            loadCsvFile();
        end

        if isempty(csvData)
            return;
        end

        if isempty(timerObj) || ~isvalid(timerObj)
            timerObj = timer( ...
                'ExecutionMode', 'fixedSpacing', ...
                'Period', 1.0, ...
                'TimerFcn', @(~, ~) stepCsvOnce());
        end

        if strcmp(timerObj.Running, 'off')
            start(timerObj);
            statusLabel.Text = 'Status: CSV stream running';
        end
    end

%% Callback: pause CSV stream
    function pauseCsvStream(~, ~)
        stopTimer();
        statusLabel.Text = 'Status: CSV stream paused';
    end

%% Callback: step one CSV row
    function stepCsvOnce(~, ~)
        if isempty(csvData)
            loadCsvFile();
        end

        if isempty(csvData)
            return;
        end

        if csvIndex >= height(csvData)
            stopTimer();
            statusLabel.Text = 'Status: end of CSV stream';
            return;
        end

        csvIndex = csvIndex + 1;

        newRow = csvData(csvIndex, predictorNames);
        updateDashboard(newRow, "CSV stream", csvIndex);

        rowLabel.Text = sprintf('CSV row: %d / %d', csvIndex, height(csvData));
    end

%% Callback: reset CSV stream
    function resetCsvStream(~, ~)
        stopTimer();
        csvIndex = 0;

        if ~isempty(csvData)
            rowLabel.Text = sprintf('CSV row: 0 / %d', height(csvData));
        else
            rowLabel.Text = 'CSV row: 0 / 0';
        end

        statusLabel.Text = 'Status: CSV stream reset';
    end

%% Callback: manual prediction
    function predictManualRow(~, ~)
        inputValues = zeros(1, numel(predictorNames));

        for k = 1:numel(predictorNames)
            inputValues(k) = inputFields(k).Value;
        end

        newRow = array2table(inputValues, 'VariableNames', predictorNames);

        updateDashboard(newRow, "Manual single row", 1);
    end

%% Callback: reset manual input
    function resetManualInput(~, ~)
        for k = 1:numel(predictorNames)
            featureName = predictorNames{k};

            if isKey(defaultValues, featureName)
                inputFields(k).Value = defaultValues(featureName);
            else
                inputFields(k).Value = 0;
            end
        end

        predictManualRow();
    end

%% Callback: clear history
    function clearHistory(~, ~)
        stopTimer();

        historyTable = table();
        historyTableUI.Data = table();

        if isfile(historyFile)
            delete(historyFile);
        end

        cla(riskAxes);
        title(riskAxes, 'Risk Score Trend');
        xlabel(riskAxes, 'Prediction step');
        ylabel(riskAxes, 'Risk level');
        ylim(riskAxes, [0 3]);
        yticks(riskAxes, [1 2 3]);
        yticklabels(riskAxes, {'Low', 'Medium', 'High'});
        grid(riskAxes, 'on');

        statusLabel.Text = 'Status: history cleared';
    end

%% Main function: update dashboard
    function updateDashboard(newRow, sourceName, sourceIndex)

        qualityRisk = string(predict(qualityModel, newRow));
        maintenanceRisk = string(predict(maintenanceModel, newRow));

        qScore = riskToNumber(qualityRisk);
        mScore = riskToNumber(maintenanceRisk);

        qualityLabel.Text = sprintf('PCB Quality Risk: %s', qualityRisk);
        maintenanceLabel.Text = sprintf('Maintenance Risk: %s', maintenanceRisk);

        qualityScoreLabel.Text = sprintf('%d / 3', qScore);
        maintenanceScoreLabel.Text = sprintf('%d / 3', mScore);

        qualityLamp.Color = riskToColor(qualityRisk);
        maintenanceLamp.Color = riskToColor(maintenanceRisk);

        currentSourceLabel.Text = sprintf('Current source: %s, row %d', sourceName, sourceIndex);
        lastUpdateLabel.Text = sprintf('Last update: %s', datestr(now, 'HH:MM:SS'));

        diagnosisBox.Value = cellstr(getDiagnosticCauses(newRow));
        recommendationBox.Value = cellstr(getRecommendedActions(qualityRisk, maintenanceRisk));

        resultRow = buildResultRow(newRow, sourceName, sourceIndex, ...
            qualityRisk, maintenanceRisk, qScore, mScore);

        appendToHistory(resultRow);

        updateRiskTrend();

        drawnow limitrate;
    end

%% Build result row
    function resultRow = buildResultRow(newRow, sourceName, sourceIndex, ...
            qualityRisk, maintenanceRisk, qScore, mScore)

        metaTable = table( ...
            string(sourceName), ...
            sourceIndex, ...
            'VariableNames', {'Source', 'SourceIndex'});

        resultRow = [metaTable, newRow];

        resultRow.PredictedQualityRisk = qualityRisk;
        resultRow.PredictedMaintenanceRisk = maintenanceRisk;

        resultRow.QualityRiskScore = qScore;
        resultRow.MaintenanceRiskScore = mScore;

        resultRow.QualityWarningLamp = riskToLampText(qualityRisk);
        resultRow.MaintenanceWarningLamp = riskToLampText(maintenanceRisk);

        resultRow.BinaryQualityWarning = riskToBinary(qualityRisk);
        resultRow.BinaryMaintenanceWarning = riskToBinary(maintenanceRisk);

        resultRow.PossibleDiagnosticCauses = strjoin(getDiagnosticCauses(newRow), " | ");
        resultRow.RecommendedActions = strjoin(getRecommendedActions(qualityRisk, maintenanceRisk), " | ");
    end

%% Append history
    function appendToHistory(resultRow)

        historyIndex = height(historyTable) + 1;
        resultRow.HistoryIndex = historyIndex;
        resultRow = movevars(resultRow, 'HistoryIndex', 'Before', 1);

        if isempty(historyTable)
            historyTable = resultRow;
        else
            historyTable = [historyTable; resultRow]; %#ok<AGROW>
        end

        historyTableUI.Data = historyTable;

        writetable(historyTable, historyFile);
    end

%% Update risk trend chart
    function updateRiskTrend()

        if isempty(historyTable)
            return;
        end

        cla(riskAxes);

        plot(riskAxes, historyTable.HistoryIndex, historyTable.QualityRiskScore, ...
            '-o', 'LineWidth', 1.4);
        hold(riskAxes, 'on');

        plot(riskAxes, historyTable.HistoryIndex, historyTable.MaintenanceRiskScore, ...
            '-s', 'LineWidth', 1.4);
        hold(riskAxes, 'off');

        ylim(riskAxes, [0 3]);
        yticks(riskAxes, [1 2 3]);
        yticklabels(riskAxes, {'Low', 'Medium', 'High'});
        xlabel(riskAxes, 'Prediction step');
        ylabel(riskAxes, 'Risk level');
        title(riskAxes, 'Risk Score Trend');
        legend(riskAxes, {'Quality Risk', 'Maintenance Risk'}, 'Location', 'best');
        grid(riskAxes, 'on');
    end

%% Close dashboard
    function closeDashboard(~, ~)
        stopTimer();

        if ~isempty(timerObj) && isvalid(timerObj)
            delete(timerObj);
        end

        delete(fig);
    end

%% Stop timer safely
    function stopTimer()
        if ~isempty(timerObj) && isvalid(timerObj)
            if strcmp(timerObj.Running, 'on')
                stop(timerObj);
            end
        end
    end
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

%% Local function: risk label to colour
function c = riskToColor(riskLabel)

switch string(riskLabel)
    case "Low"
        c = [0.1 0.7 0.2];      % green
    case "Medium"
        c = [1.0 0.75 0.0];     % amber
    case "High"
        c = [0.9 0.1 0.1];      % red
    otherwise
        c = [0.5 0.5 0.5];      % grey
end
end

%% Local function: risk label to lamp text
function lamp = riskToLampText(riskLabel)

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

%% Local function: diagnostic causes
function causes = getDiagnosticCauses(newCondition)

causes = strings(0, 1);

if newCondition.MaxTempError > 25
    causes(end+1, 1) = "- Large maximum temperature error: oven temperature may be far from the target profile.";
elseif newCondition.MeanTempError > 12
    causes(end+1, 1) = "- High average temperature error: temperature control may be unstable.";
end

if newCondition.TempFluctuation > 8
    causes(end+1, 1) = "- High temperature fluctuation: possible unstable heating or sensor disturbance.";
end

if abs(newCondition.AvgConveyorSpeed - 0.85) > 0.04
    causes(end+1, 1) = "- Abnormal conveyor speed: PCB heating time may be too short or too long.";
end

if newCondition.AvgHeaterPower > 75
    causes(end+1, 1) = "- High heater power: possible heater ageing or high thermal load.";
end

if newCondition.PeakMotorCurrent > 3.15
    causes(end+1, 1) = "- High motor current: possible conveyor, fan or motor load problem.";
end

if newCondition.RMSVibration > 0.23
    causes(end+1, 1) = "- High vibration: possible bearing wear, fan imbalance or mechanical looseness.";
end

if newCondition.OperatingHours > 580 && ...
   (newCondition.RMSVibration > 0.20 || ...
    newCondition.PeakMotorCurrent > 3.00 || ...
    newCondition.AvgHeaterPower > 70)

    causes(end+1, 1) = "- High operating hours with abnormal signals: equipment ageing may increase maintenance risk.";
end

if isempty(causes)
    causes = "- No major abnormal sensor pattern detected in this example condition.";
end
end

%% Local function: recommended actions
function actions = getRecommendedActions(qualityRisk, maintenanceRisk)

actions = strings(0, 1);

if qualityRisk == "High"
    actions(end+1, 1) = "- Quality risk HIGH: inspect sample PCBs and check the reflow temperature profile.";
elseif qualityRisk == "Medium"
    actions(end+1, 1) = "- Quality risk MEDIUM: monitor the next batch and check temperature deviation.";
else
    actions(end+1, 1) = "- Quality risk LOW: continue normal production.";
end

if maintenanceRisk == "High"
    actions(end+1, 1) = "- Maintenance risk HIGH: schedule inspection of heater, fan, motor or conveyor system.";
elseif maintenanceRisk == "Medium"
    actions(end+1, 1) = "- Maintenance risk MEDIUM: monitor vibration and motor current trends.";
else
    actions(end+1, 1) = "- Maintenance risk LOW: no immediate maintenance action is needed.";
end
end