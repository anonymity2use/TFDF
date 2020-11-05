function [Acc,acc_iter,Beta,Yt_pred,MMD_distance_iter] = MSDI(Xs,Ys,Xt,Yt,options,mode,src,tgt)



%% Inputs:
%%% Xs      : Source domain feature matrix, n * dim
%%% Ys      : Source domain label matrix, n * 1
%%% Xt      : Target domain feature matrix, m * dim
%%% Yt      : Target domain label matrix, m * 1 (only used for testing accuracy)
%%% options : algorithm options:
%%%%% options.d      :  dimension after manifold feature learning (default: 20)
%%%%% options.T      :  number of iteration (default: 10)
%%%%% options.lambda :  lambda in the paper (default: 10)
%%%%% options.eta    :  eta in the paper (default: 0.1)
%%%%% options.rho    :  rho in the paper (default: 1.0)
%%%%% options.base   :  base classifier for soft labels (default: NN)

%% Outputs:
%%%% Acc      :  Final accuracy value
%%%% acc_iter :  Accuracy value list of all iterations, T * 1
%%%% Beta     :  Cofficient matrix
%%%% Yt_pred  :  Prediction labels for target domain

%% Load algorithm options
    addpath(genpath('liblinear/matlab'));
%% Algorithm starts here
    fprintf('MSDI starts...\n');
    
    %% Load algorithm options
    if ~isfield(options,'p')
        options.p = 10;
    end
    if ~isfield(options,'eta')
        options.eta = 0.1;
    end
    if ~isfield(options,'lambda')
        options.lambda = 1.0;
    end
    if ~isfield(options,'rho')
        options.rho = 1.0;
    end
    if ~isfield(options,'T')
        options.T = 10;
    end
    if ~isfield(options,'d')
        options.d = 20;
    end
    if ~isfield(options,'gamma')
        options.gamma = 0.1;
    end
    if ~isfield(options,'delta')
        options.gamma = 0;
    end
    MMCD_distance = inf;
    
    % Manifold feature learning
    [Xs_new,Xt_new,~] = GFK_Map(Xs,Xt,options.d);
    Xs = double(Xs_new'); %琛屽彉鍒?
    Xt = double(Xt_new'); %琛屽彉鍒?

    X = [Xs,Xt];
    n = size(Xs,2);
    m = size(Xt,2);
    C = length(unique(Ys)); %绫绘暟閲?
    acc_iter = [];
    MMD_distance_iter = [];
    
    YY = [];
    for c = 1 : C
        YY = [YY,Ys==c];
    end
    YY = [YY;zeros(m,C)];

    %% Data normalization
    X = X * diag(sparse(1 ./ sqrt(sum(X.^2))));

    %% Construct graph Laplacian
    if options.rho > 0
        manifold.k = options.p;
        manifold.Metric = 'Cosine';
        manifold.NeighborMode = 'KNN';
        manifold.WeightMode = 'Cosine';
        W = lapgraph(X',manifold);
        Dw = diag(sparse(sqrt(1 ./ sum(W)))); % D鐨?-1/2娆℃柟锛岃繖涔堝啓璁＄畻鐨勫揩
        L = eye(n + m) - Dw * W * Dw;
    else
        L = 0;
    end

    % Generate soft labels for the target domain
      knn_model = fitcknn(X(:,1:n)',Ys,'NumNeighbors',1);
      Cls = knn_model.predict(X(:,n + 1:end)'); % predict Xt
    % Linear 线性分类器     
%       model = train(Ys,sparse(X(:,1:n)'),'-s 2 -c 0.7 -q 1');
%       [Cls,~] = predict(Yt,sparse(X(:,n+1:end)'),model);
      
    % neural network     
    
    % TCA 鍘诲垵濮嬪寲Yt锛? 

    % Construct kernel
%     K = kernel_meda('rbf',X,sqrt(sum(sum(X .^ 2).^0.5)/(n + m)));

    % multi kernel
    K = multi_kernel(X, sqrt(sum(sum(X .^ 2).^0.5)/(n + m)));
    
    E = diag(sparse([ones(n,1);zeros(m,1)]));

    for t = 1 : options.T
        % Estimate mu
        mu = estimate_mu(Xs',Ys,Xt',Cls);
%         mu = options.mu;
        % Construct MMD matrix
        e = [1 / n * ones(n,1); -1 / m * ones(m,1)];
        M0 = e * e' * length(unique(Ys));
        Mc = 0;
        % Z0
        Z0 = [-1/n^2 * ones(n) + diag(1/n * ones(n,1)), zeros(n,m);
             zeros(m,n)                              , 1/m^2 * ones(m) + diag(-1/m * ones(m,1))];
        Z=0;
        
        H = eye(n+m) - ones(n+m)/(n+m);

        for c = reshape(unique(Ys),1,length(unique(Ys)))
            e = zeros(n + m,1);
            e(Ys == c) = 1 / length(find(Ys == c));  % 1 / Nsc
            e(n + find(Cls == c)) = -1 / length(find(Cls == c)); % - 1 / Ntc
            e(isinf(e)) = 0;
            Mc = Mc + e * e';
            
            Nsc = length(find(Ys == c));
            Ntc = length(find(Cls == c));
            
            Ys_logical_matrix = (Ys == c) * (Ys == c)';
            Yt_logical_matrix = (Cls == c) * (Cls == c)';

            Zc = [Ys_logical_matrix .* (-1/Nsc^2 * ones(n) + diag(1/Nsc * ones(n,1))), zeros(n,m);
                  zeros(m,n)                                                         ,Yt_logical_matrix .* (1/Ntc^2 * ones(m) + diag(-1/Ntc * ones(m,1)))];
            Zc(isnan(Zc)) = 0;
            Z = Z + Zc;
        end
%        M = (1 - mu) * M0 + mu * Mc;
        V = (1 - mu) * (M0 + options.gamma * (Z0 * K * K * Z0)) + mu * (Mc + options.gamma * (Z * K * K * Z)) ;
        % norm function has bug, so we compute another way
        V = V / sqrt(sumsqr(V));
        
        % Multi Kernel MMCD
        Beta = ((E + options.lambda * V + options.rho * L + options.delta * H) * K + options.eta * speye(n + m,n + m)) \ (E * YY);

        % compute MMD distance 
        MMD_distance = trace(Beta' * K * Mc * K * Beta);
        MMD_distance_iter = [MMD_distance_iter;MMD_distance];
        % compute MMCD distance
        MMCD_distance1 = MMCD_distance;
        MMCD_distance = norm(Beta' * K * Z * K * Beta, 'fro')^2;
        
        % Compute accuracy Acc1
        F = K * Beta;
        [~,Cls] = max(F,[],2); % predict Xt
        Acc = numel(find(Cls(n+1:end)==Yt)) / m;
        if  strcmp(mode, 'init') == 1,
                Beta_init = Beta;
                save([src,'+',tgt,'.mat'],'Beta_init');
        end
        if  strcmp(mode, 'init_zero') == 1,
                Beta_init = Beta;
                save([src,'+',tgt,'.mat'],'Beta_init');
        end
        if  strcmp(mode, 'init_plot') == 1,
                Beta_init_plot = Beta;
                save([src,'+',tgt,'_plot.mat'],'Beta_init_plot');
        end
        
               
        % 输出
        Cls = Cls(n+1:end);
        acc_iter = [acc_iter;Acc];
        fprintf('Iteration:[%02d]>>mu=%.2f,Acc=%f,MMD=%f,MMCD=%f\n',t,mu,Acc,MMD_distance,MMCD_distance);
    end
    Yt_pred = Cls;
    Acc = max(acc_iter);
    fprintf('MSDI ends!\n');
end

function K = kernel_meda(ker,X,sigma)
    switch ker
        case 'linear'
            K = X' * X;
        case 'rbf'
            n1sq = sum(X.^2,1);
            n1 = size(X,2);
            D = (ones(n1,1)*n1sq)' + ones(n1,1)*n1sq -2*X'*X;
            K = exp(-D/(2*sigma^2));        
        case 'sam'
            D = X'*X;
            K = exp(-acos(D).^2/(2*sigma^2));
        otherwise
            error(['Unsupported kernel ' ker])
    end
    
end
