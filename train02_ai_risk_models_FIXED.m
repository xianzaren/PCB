%% train02_ai_risk_models_FIXED.m
% Trains and compares five supervised ML models for:
% 1. PCB quality risk prediction
% 2. Machine maintenance risk prediction
%
% Compared models:
% Decision Tree, Random Forest, Gradient Boosting, KNN, SVM
%
% Selection score:
% 0.70 * Macro-F1 + 0.30 * High-risk Recall

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

classNames = ["Low", "Medium", "High"];

X = T(:, predictorNames);

Yq = categorical(string(T.QualityRisk), classNames);
Ym = categorical(string(T.MaintenanceRisk), classNames);

fprintf('\nDataset size: %d samples\n', height(T));

%% Model list
modelNames = [
    "Decision Tree"
    "Random Forest"
    "Gradient Boosting"
    "KNN"
    "SVM"
];

%% Evaluate models for Quality Risk
[trainIdxQ, testIdxQ] = stratifiedHoldout(Yq, 0.30);

XqTrain = X(trainIdxQ, :);
XqTest  = X(testIdxQ, :);

YqTrain = Yq(trainIdxQ);
YqTest  = Yq(testIdxQ);

qualityComparison = table();

qualityModelStore = cell(numel(modelNames), 1);
qualityPredStore = cell(numel(modelNames), 1);
qualityMetricsStore = cell(numel(modelNames), 1);

fprintf('\n=== Quality Risk Model Comparison ===\n');

for i = 1:numel(modelNames)

    modelName = modelNames(i);

    try
        mdl = trainOneModel(modelName, XqTrain, YqTrain, predictorNames);
        pred = predict(mdl, XqTest);

        metrics = computeMetrics(YqTest, pred, classNames);
        row = summariseModelPerformance(modelName, YqTest, pred, metrics);

        qualityComparison = [qualityComparison; row]; %#ok<AGROW>

        qualityModelStore{i} = mdl;
        qualityPredStore{i} = pred;
        qualityMetricsStore{i} = metrics;

    catch ME
        warning('Quality model %s failed: %s', modelName, ME.message);

        row = table(string(modelName), NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            'VariableNames', {'Model', 'Accuracy', 'MacroPrecision', ...
            'MacroRecall', 'MacroF1', 'HighPrecision', 'HighRecall', ...
            'SelectionScore'});

        qualityComparison = [qualityComparison; row]; %#ok<AGROW>
    end
end

disp(qualityComparison);

%% Evaluate models for Maintenance Risk
[trainIdxM, testIdxM] = stratifiedHoldout(Ym, 0.30);

XmTrain = X(trainIdxM, :);
XmTest  = X(testIdxM, :);

YmTrain = Ym(trainIdxM);
YmTest  = Ym(testIdxM);

maintenanceComparison = table();

maintenanceModelStore = cell(numel(modelNames), 1);
maintenancePredStore = cell(numel(modelNames), 1);
maintenanceMetricsStore = cell(numel(modelNames), 1);

fprintf('\n=== Maintenance Risk Model Comparison ===\n');

for i = 1:numel(modelNames)

    modelName = modelNames(i);

    try
        mdl = trainOneModel(modelName, XmTrain, YmTrain, predictorNames);
        pred = predict(mdl, XmTest);

        metrics = computeMetrics(YmTest, pred, classNames);
        row = summariseModelPerformance(modelName, YmTest, pred, metrics);

        maintenanceComparison = [maintenanceComparison; row]; %#ok<AGROW>

        maintenanceModelStore{i} = mdl;
        maintenancePredStore{i} = pred;
        maintenanceMetricsStore{i} = metrics;

    catch ME
        warning('Maintenance model %s failed: %s', modelName, ME.message);

        row = table(string(modelName), NaN, NaN, NaN, NaN, NaN, NaN, NaN, ...
            'VariableNames', {'Model', 'Accuracy', 'MacroPrecision', ...
            'MacroRecall', 'MacroF1', 'HighPrecision', 'HighRecall', ...
            'SelectionScore'});

        maintenanceComparison = [maintenanceComparison; row]; %#ok<AGROW>
    end
end

disp(maintenanceComparison);

%% Select best models
qualityScores = qualityComparison.SelectionScore;
qualityScores(isnan(qualityScores)) = -Inf;

maintenanceScores = maintenanceComparison.SelectionScore;
maintenanceScores(isnan(maintenanceScores)) = -Inf;

if all(isinf(qualityScores))
    error('All quality risk models failed. Please check toolbox availability and input data.');
end

if all(isinf(maintenanceScores))
    error('All maintenance risk models failed. Please check toolbox availability and input data.');
end

[~, bestQIdx] = max(qualityScores);
[~, bestMIdx] = max(maintenanceScores);

qualityModelName = qualityComparison.Model(bestQIdx);
maintenanceModelName = maintenanceComparison.Model(bestMIdx);

fprintf('\nSelected Quality Risk model: %s\n', qualityModelName);
fprintf('Selected Maintenance Risk model: %s\n', maintenanceModelName);

%% Train final selected models on the full dataset
qualityModel = trainOneModel(qualityModelName, X, Yq, predictorNames);
maintenanceModel = trainOneModel(maintenanceModelName, X, Ym, predictorNames);

%% Save selected models
save(fullfile(outDir, 'trained_risk_models_FIXED.mat'), ...
    'qualityModel', ...
    'maintenanceModel', ...
    'predictorNames', ...
    'qualityModelName', ...
    'maintenanceModelName', ...
    'qualityComparison', ...
    'maintenanceComparison');

%% Save model comparison tables
writetable(qualityComparison, fullfile(outDir, 'quality_model_comparison_FIXED.csv'));
writetable(maintenanceComparison, fullfile(outDir, 'maintenance_model_comparison_FIXED.csv'));

%% Save selected model metrics
bestQPred = qualityPredStore{bestQIdx};
bestMPred = maintenancePredStore{bestMIdx};

qualityMetrics = qualityMetricsStore{bestQIdx};
maintenanceMetrics = maintenanceMetricsStore{bestMIdx};

writetable(qualityMetrics, fullfile(outDir, 'quality_metrics_BEST_MODEL.csv'));
writetable(maintenanceMetrics, fullfile(outDir, 'maintenance_metrics_BEST_MODEL.csv'));

%% Confusion charts for selected models
fig1 = figure('Name', 'Quality Risk Confusion Matrix');
confusionchart(YqTest, bestQPred);
title(['Quality Risk Confusion Matrix - ' char(qualityModelName)]);
saveas(fig1, fullfile(outDir, 'quality_confusion_FIXED.png'));

fig2 = figure('Name', 'Maintenance Risk Confusion Matrix');
confusionchart(YmTest, bestMPred);
title(['Maintenance Risk Confusion Matrix - ' char(maintenanceModelName)]);
saveas(fig2, fullfile(outDir, 'maintenance_confusion_FIXED.png'));

%% Metrics bar charts for selected models
fig3 = figure('Name', 'Quality Risk Metrics');
bar(categorical(string(qualityMetrics.Class)), ...
    [qualityMetrics.Precision, qualityMetrics.Recall, qualityMetrics.F1Score]);
ylim([0 1]);
ylabel('Score');
title(['Quality Risk Metrics - ' char(qualityModelName)]);
legend({'Precision', 'Recall', 'F1-score'}, 'Location', 'best');
grid on;
saveas(fig3, fullfile(outDir, 'quality_metrics_bar_FIXED.png'));

fig4 = figure('Name', 'Maintenance Risk Metrics');
bar(categorical(string(maintenanceMetrics.Class)), ...
    [maintenanceMetrics.Precision, maintenanceMetrics.Recall, maintenanceMetrics.F1Score]);
ylim([0 1]);
ylabel('Score');
title(['Maintenance Risk Metrics - ' char(maintenanceModelName)]);
legend({'Precision', 'Recall', 'F1-score'}, 'Location', 'best');
grid on;
saveas(fig4, fullfile(outDir, 'maintenance_metrics_bar_FIXED.png'));

%% Model comparison bar charts
fig5 = figure('Name', 'Quality Model Comparison');
bar(categorical(string(qualityComparison.Model)), qualityComparison.SelectionScore);
ylabel('Selection Score');
title('Quality Risk Model Comparison');
grid on;
saveas(fig5, fullfile(outDir, 'quality_model_comparison_FIXED.png'));

fig6 = figure('Name', 'Maintenance Model Comparison');
bar(categorical(string(maintenanceComparison.Model)), maintenanceComparison.SelectionScore);
ylabel('Selection Score');
title('Maintenance Risk Model Comparison');
grid on;
saveas(fig6, fullfile(outDir, 'maintenance_model_comparison_FIXED.png'));

%% Feature importance for selected models
% Permutation importance is used, so it works for tree models, KNN and SVM.
qualityImportanceTable = permutationImportance( ...
    qualityModelStore{bestQIdx}, XqTest, YqTest, predictorNames);

maintenanceImportanceTable = permutationImportance( ...
    maintenanceModelStore{bestMIdx}, XmTest, YmTest, predictorNames);

writetable(qualityImportanceTable, fullfile(outDir, 'quality_feature_importance_FIXED.csv'));
writetable(maintenanceImportanceTable, fullfile(outDir, 'maintenance_feature_importance_FIXED.csv'));

fig7 = figure('Name', 'Quality Risk Feature Importance');
bar(qualityImportanceTable.Importance);
set(gca, 'XTick', 1:numel(predictorNames));
set(gca, 'XTickLabel', qualityImportanceTable.Feature);
set(gca, 'XTickLabelRotation', 45);
ylabel('Permutation Importance');
title(['Feature Importance - Quality Risk - ' char(qualityModelName)]);
grid on;
saveas(fig7, fullfile(outDir, 'quality_feature_importance_FIXED.png'));

fig8 = figure('Name', 'Maintenance Risk Feature Importance');
bar(maintenanceImportanceTable.Importance);
set(gca, 'XTick', 1:numel(predictorNames));
set(gca, 'XTickLabel', maintenanceImportanceTable.Feature);
set(gca, 'XTickLabelRotation', 45);
ylabel('Permutation Importance');
title(['Feature Importance - Maintenance Risk - ' char(maintenanceModelName)]);
grid on;
saveas(fig8, fullfile(outDir, 'maintenance_feature_importance_FIXED.png'));

%% Display output file locations
disp(' ');
disp('Saved selected models, model comparison results, metrics, confusion matrices and feature importance outputs.');
disp('Key output files:');
disp(fullfile(outDir, 'trained_risk_models_FIXED.mat'));
disp(fullfile(outDir, 'quality_model_comparison_FIXED.csv'));
disp(fullfile(outDir, 'maintenance_model_comparison_FIXED.csv'));
disp(fullfile(outDir, 'quality_confusion_FIXED.png'));
disp(fullfile(outDir, 'maintenance_confusion_FIXED.png'));
disp(fullfile(outDir, 'quality_feature_importance_FIXED.png'));
disp(fullfile(outDir, 'maintenance_feature_importance_FIXED.png'));

%% Local function: train one model
function mdl = trainOneModel(modelName, XTrain, YTrain, predictorNames)

    p = numel(predictorNames);

    switch char(modelName)

        case 'Decision Tree'
            mdl = fitctree(XTrain, YTrain, ...
                'MinLeafSize', 5, ...
                'MaxNumSplits', 30);

        case 'Random Forest'
            numTrees = 150;
            numPredictorsToSample = max(1, ceil(sqrt(p)));

            treeTemplate = templateTree( ...
                'MinLeafSize', 3, ...
                'MaxNumSplits', 60, ...
                'NumVariablesToSample', numPredictorsToSample);

            mdl = fitcensemble(XTrain, YTrain, ...
                'Method', 'Bag', ...
                'NumLearningCycles', numTrees, ...
                'Learners', treeTemplate);

        case 'Gradient Boosting'
            treeTemplate = templateTree( ...
                'MinLeafSize', 5, ...
                'MaxNumSplits', 20);

            mdl = fitcensemble(XTrain, YTrain, ...
                'Method', 'AdaBoostM2', ...
                'NumLearningCycles', 100, ...
                'LearnRate', 0.1, ...
                'Learners', treeTemplate);

        case 'KNN'
            mdl = fitcknn(XTrain, YTrain, ...
                'NumNeighbors', 5, ...
                'Distance', 'euclidean', ...
                'Standardize', true);

        case 'SVM'
            svmTemplate = templateSVM( ...
                'KernelFunction', 'rbf', ...
                'KernelScale', 'auto', ...
                'BoxConstraint', 1, ...
                'Standardize', true);

            mdl = fitcecoc(XTrain, YTrain, ...
                'Learners', svmTemplate, ...
                'Coding', 'onevsone');

        otherwise
            error('Unknown model name: %s', modelName);
    end
end

%% Local function: stratified holdout split
function [trainIdx, testIdx] = stratifiedHoldout(Y, testRatio)

    Ystr = string(Y);
    classes = unique(Ystr);

    trainIdx = [];
    testIdx = [];

    for i = 1:numel(classes)
        idx = find(Ystr == classes(i));
        idx = idx(randperm(numel(idx)));

        if numel(idx) <= 1
            trainIdx = [trainIdx; idx]; %#ok<AGROW>
        else
            nTest = round(testRatio * numel(idx));
            nTest = max(1, nTest);
            nTest = min(nTest, numel(idx)-1);

            testIdx = [testIdx; idx(1:nTest)]; %#ok<AGROW>
            trainIdx = [trainIdx; idx(nTest+1:end)]; %#ok<AGROW>
        end
    end

    trainIdx = trainIdx(randperm(numel(trainIdx)));
    testIdx = testIdx(randperm(numel(testIdx)));
end

%% Local function: summarise model performance
function row = summariseModelPerformance(modelName, yTrue, yPred, metrics)

    accuracy = mean(string(yTrue) == string(yPred));

    macroPrecision = mean(metrics.Precision);
    macroRecall = mean(metrics.Recall);
    macroF1 = mean(metrics.F1Score);

    highRow = metrics(metrics.Class == "High", :);

    if isempty(highRow)
        highPrecision = 0;
        highRecall = 0;
    else
        highPrecision = highRow.Precision;
        highRecall = highRow.Recall;
    end

    selectionScore = 0.70 * macroF1 + 0.30 * highRecall;

    row = table(string(modelName), accuracy, macroPrecision, macroRecall, ...
        macroF1, highPrecision, highRecall, selectionScore, ...
        'VariableNames', {'Model', 'Accuracy', 'MacroPrecision', ...
        'MacroRecall', 'MacroF1', 'HighPrecision', 'HighRecall', ...
        'SelectionScore'});
end

%% Local function: calculate metrics
function metricsTable = computeMetrics(yTrue, yPred, classNames)

    yTrue = string(yTrue);
    yPred = string(yPred);

    nClass = numel(classNames);

    Class = strings(nClass, 1);
    TP = zeros(nClass, 1);
    FP = zeros(nClass, 1);
    FN = zeros(nClass, 1);
    TN = zeros(nClass, 1);

    Precision = zeros(nClass, 1);
    Recall = zeros(nClass, 1);
    F1Score = zeros(nClass, 1);
    FalsePositiveCount = zeros(nClass, 1);
    FalseNegativeCount = zeros(nClass, 1);

    for i = 1:nClass
        cls = string(classNames(i));
        Class(i) = cls;

        TP(i) = sum(yPred == cls & yTrue == cls);
        FP(i) = sum(yPred == cls & yTrue ~= cls);
        FN(i) = sum(yPred ~= cls & yTrue == cls);
        TN(i) = sum(yPred ~= cls & yTrue ~= cls);

        Precision(i) = safeDivide(TP(i), TP(i) + FP(i));
        Recall(i) = safeDivide(TP(i), TP(i) + FN(i));
        F1Score(i) = safeDivide(2 * Precision(i) * Recall(i), Precision(i) + Recall(i));

        FalsePositiveCount(i) = FP(i);
        FalseNegativeCount(i) = FN(i);
    end

    metricsTable = table(Class, TP, FP, FN, TN, Precision, Recall, ...
        F1Score, FalsePositiveCount, FalseNegativeCount);
end

%% Local function: permutation feature importance
function importanceTable = permutationImportance(mdl, XTest, YTest, predictorNames)

    rng(42);

    baselinePred = predict(mdl, XTest);
    baselineAcc = mean(string(baselinePred) == string(YTest));

    nFeatures = numel(predictorNames);
    importance = zeros(nFeatures, 1);

    nRepeats = 5;

    for j = 1:nFeatures

        scoreDrop = zeros(nRepeats, 1);

        for r = 1:nRepeats
            XPerm = XTest;
            colName = predictorNames{j};

            shuffledValues = XPerm.(colName);
            shuffledValues = shuffledValues(randperm(height(XPerm)));

            XPerm.(colName) = shuffledValues;

            permPred = predict(mdl, XPerm);
            permAcc = mean(string(permPred) == string(YTest));

            scoreDrop(r) = baselineAcc - permAcc;
        end

        importance(j) = max(mean(scoreDrop), 0);
    end

    importanceTable = table(string(predictorNames(:)), importance, ...
        'VariableNames', {'Feature', 'Importance'});
end

%% Local function: safe division
function value = safeDivide(a, b)

    if b == 0
        value = 0;
    else
        value = a / b;
    end
end

disp('Next run: 03.m');