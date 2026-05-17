%% train02_ai_risk_models_FIXED.m
% Train Random Forest style models for:
% 1. PCB quality risk prediction
% 2. Machine maintenance risk prediction
%
% This version uses Bagged Decision Trees, which is a Random Forest style model.
% It also calculates more evaluation metrics:
% Accuracy, Precision, Recall, F1-score, False Positive Count, False Negative Count.

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

%% Load dataset

dataFile = fullfile(outDir, 'sensor_features_with_labels_FIXED.mat');

if ~isfile(dataFile)
    error('Dataset not found. Run generate01_sensor_data_from_simulink_FIXED.m first.');
end

load(dataFile, 'T');

%% Define predictors and labels

predictorNames = { ...
    'MeanTempError', ...
    'MaxTempError', ...
    'TempFluctuation', ...
    'AvgHeaterPower', ...
    'AvgConveyorSpeed', ...
    'PeakMotorCurrent', ...
    'RMSVibration', ...
    'OperatingHours'};

X = T(:, predictorNames);

Yq = T.QualityRisk;
Ym = T.MaintenanceRisk;

%% Check sample size

n = height(T);

fprintf('\nDataset size: %d samples\n', n);

if n < 50
    warning(['The dataset is small. Metrics may be unstable. ', ...
             'Consider increasing the simulation length or adding more scenarios.']);
end

%% Train / test split
% Use a simple 70/30 hold-out split.
% This gives a more realistic evaluation than testing only on the training data.

idx = randperm(n);
nTrain = round(0.7 * n);

trainIdx = idx(1:nTrain);
testIdx = idx(nTrain+1:end);

XTrain = X(trainIdx, :);
XTest  = X(testIdx, :);

YqTrain = Yq(trainIdx);
YqTest  = Yq(testIdx);

YmTrain = Ym(trainIdx);
YmTest  = Ym(testIdx);

fprintf('Training samples: %d\n', height(XTrain));
fprintf('Test samples: %d\n', height(XTest));

%% Train Random Forest style models
% MATLAB does not use the name "Random Forest" directly here.
% Bagged Trees with random predictor sampling is commonly used as a Random Forest style model.

numTrees = 100;
numPredictorsToSample = max(1, round(sqrt(numel(predictorNames))));

treeTemplate = templateTree( ...
    'MinLeafSize', 1, ...
    'NumVariablesToSample', numPredictorsToSample);

qualityModel = fitcensemble(XTrain, YqTrain, ...
    'Method', 'Bag', ...
    'NumLearningCycles', numTrees, ...
    'Learners', treeTemplate);

maintenanceModel = fitcensemble(XTrain, YmTrain, ...
    'Method', 'Bag', ...
    'NumLearningCycles', numTrees, ...
    'Learners', treeTemplate);

%% Predict on test data

predQ = predict(qualityModel, XTest);
predM = predict(maintenanceModel, XTest);

%% Overall accuracy

accQ = mean(predQ == YqTest);
accM = mean(predM == YmTest);

fprintf('\n=== Test Accuracy ===\n');
fprintf('Quality risk model test accuracy: %.2f%%\n', accQ * 100);
fprintf('Maintenance risk model test accuracy: %.2f%%\n', accM * 100);

%% More evaluation metrics
% One-vs-rest metrics are calculated for each class:
% Low, Medium, High.
%
% For predictive maintenance, the High Risk class is especially important,
% because missed High Risk cases can lead to unplanned downtime.

qualityClassOrder = categories(Yq);
maintenanceClassOrder = categories(Ym);

qualityMetrics = computeMetrics(YqTest, predQ, qualityClassOrder);
maintenanceMetrics = computeMetrics(YmTest, predM, maintenanceClassOrder);

fprintf('\n=== Quality Risk Metrics by Class ===\n');
disp(qualityMetrics);

fprintf('\n=== Maintenance Risk Metrics by Class ===\n');
disp(maintenanceMetrics);

%% Extract High Risk metrics

fprintf('\n=== High Risk Class Focus ===\n');

highQuality = qualityMetrics(strcmp(string(qualityMetrics.Class), "High"), :);
highMaintenance = maintenanceMetrics(strcmp(string(maintenanceMetrics.Class), "High"), :);

if ~isempty(highQuality)
    fprintf('\nQuality Risk - High class:\n');
    disp(highQuality);
end

if ~isempty(highMaintenance)
    fprintf('\nMaintenance Risk - High class:\n');
    disp(highMaintenance);
end

%% Save trained models
% The file name stays the same, so run03_ai_prediction_demo_FIXED.m can still load it.

save(fullfile(outDir, 'trained_risk_models_FIXED.mat'), ...
    'qualityModel', ...
    'maintenanceModel', ...
    'predictorNames');

%% Save metric tables

writetable(qualityMetrics, fullfile(outDir, 'quality_metrics_RANDOM_FOREST.csv'));
writetable(maintenanceMetrics, fullfile(outDir, 'maintenance_metrics_RANDOM_FOREST.csv'));

summaryTable = table(accQ, accM, numTrees, numPredictorsToSample, ...
    'VariableNames', { ...
    'QualityRiskAccuracy', ...
    'MaintenanceRiskAccuracy', ...
    'NumberOfTrees', ...
    'NumPredictorsToSample'});

writetable(summaryTable, fullfile(outDir, 'model_accuracy_summary_FIXED.csv'));

%% Confusion matrix for quality risk

fig1 = figure('Name', 'Quality Risk Confusion Matrix');

confusionchart(YqTest, predQ);
title('Quality Risk Prediction Confusion Matrix - Random Forest');

saveas(fig1, fullfile(outDir, 'quality_confusion_FIXED.png'));

%% Confusion matrix for maintenance risk

fig2 = figure('Name', 'Maintenance Risk Confusion Matrix');

confusionchart(YmTest, predM);
title('Maintenance Risk Prediction Confusion Matrix - Random Forest');

saveas(fig2, fullfile(outDir, 'maintenance_confusion_FIXED.png'));

%% Feature importance

qualityImportance = predictorImportance(qualityModel);
maintenanceImportance = predictorImportance(maintenanceModel);

fig3 = figure('Name', 'Quality Risk Feature Importance');

bar(qualityImportance);
set(gca, 'XTick', 1:numel(predictorNames));
set(gca, 'XTickLabel', predictorNames);
set(gca, 'XTickLabelRotation', 45);
ylabel('Importance');
title('Feature Importance - Quality Risk Model');
grid on;

saveas(fig3, fullfile(outDir, 'quality_feature_importance_FIXED.png'));

fig4 = figure('Name', 'Maintenance Risk Feature Importance');

bar(maintenanceImportance);
set(gca, 'XTick', 1:numel(predictorNames));
set(gca, 'XTickLabel', predictorNames);
set(gca, 'XTickLabelRotation', 45);
ylabel('Importance');
title('Feature Importance - Maintenance Risk Model');
grid on;

saveas(fig4, fullfile(outDir, 'maintenance_feature_importance_FIXED.png'));

%% Precision / Recall / F1 bar charts

fig5 = figure('Name', 'Quality Risk Metrics');

bar(categorical(string(qualityMetrics.Class)), ...
    [qualityMetrics.Precision, qualityMetrics.Recall, qualityMetrics.F1Score]);

ylim([0 1]);
ylabel('Score');
title('Quality Risk Metrics by Class');
legend({'Precision', 'Recall', 'F1-score'}, 'Location', 'best');
grid on;

saveas(fig5, fullfile(outDir, 'quality_metrics_bar_RANDOM_FOREST.png'));

fig6 = figure('Name', 'Maintenance Risk Metrics');

bar(categorical(string(maintenanceMetrics.Class)), ...
    [maintenanceMetrics.Precision, maintenanceMetrics.Recall, maintenanceMetrics.F1Score]);

ylim([0 1]);
ylabel('Score');
title('Maintenance Risk Metrics by Class');
legend({'Precision', 'Recall', 'F1-score'}, 'Location', 'best');
grid on;

saveas(fig6, fullfile(outDir, 'maintenance_metrics_bar_RANDOM_FOREST.png'));

%% Display output file locations

disp(' ');
disp('Saved Random Forest models and evaluation outputs in outputs folder.');
disp('Key output files:');
disp(fullfile(outDir, 'trained_risk_models_FIXED.mat'));
disp(fullfile(outDir, 'quality_confusion_FIXED.png'));
disp(fullfile(outDir, 'maintenance_confusion_FIXED.png'));
disp(fullfile(outDir, 'quality_metrics_RANDOM_FOREST.csv'));
disp(fullfile(outDir, 'maintenance_metrics_RANDOM_FOREST.csv'));
disp(fullfile(outDir, 'quality_feature_importance_FIXED.png'));
disp(fullfile(outDir, 'maintenance_feature_importance_FIXED.png'));

%% Local function: calculate one-vs-rest classification metrics

function metricsTable = computeMetrics(yTrue, yPred, classOrder)

    yTrue = categorical(yTrue);
    yPred = categorical(yPred);

    numClasses = numel(classOrder);

    Class = strings(numClasses, 1);
    TP = zeros(numClasses, 1);
    FP = zeros(numClasses, 1);
    FN = zeros(numClasses, 1);
    TN = zeros(numClasses, 1);

    Precision = zeros(numClasses, 1);
    Recall = zeros(numClasses, 1);
    F1Score = zeros(numClasses, 1);
    FalsePositiveCount = zeros(numClasses, 1);
    FalseNegativeCount = zeros(numClasses, 1);

    for i = 1:numClasses

        currentClass = categorical(classOrder(i));

        Class(i) = string(classOrder(i));

        TP(i) = sum(yPred == currentClass & yTrue == currentClass);
        FP(i) = sum(yPred == currentClass & yTrue ~= currentClass);
        FN(i) = sum(yPred ~= currentClass & yTrue == currentClass);
        TN(i) = sum(yPred ~= currentClass & yTrue ~= currentClass);

        FalsePositiveCount(i) = FP(i);
        FalseNegativeCount(i) = FN(i);

        Precision(i) = safeDivide(TP(i), TP(i) + FP(i));
        Recall(i) = safeDivide(TP(i), TP(i) + FN(i));
        F1Score(i) = safeDivide(2 * Precision(i) * Recall(i), Precision(i) + Recall(i));
    end

    metricsTable = table( ...
        Class, ...
        TP, ...
        FP, ...
        FN, ...
        TN, ...
        Precision, ...
        Recall, ...
        F1Score, ...
        FalsePositiveCount, ...
        FalseNegativeCount);
end

%% Local function: safe division

function value = safeDivide(numerator, denominator)

    if denominator == 0
        value = 0;
    else
        value = numerator / denominator;
    end
end