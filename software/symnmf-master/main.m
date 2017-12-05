% This script implement multi-source alternate clustering
clear all, close all, clc;

% Parameter Settings
% Number of nearest neighbors in self-tuning spectral clustering
nn = 7;
% range of lambda
v_lambda_range = 0:0.1:2;
% Number of latent factors;
dim_q = 4;
% tolerance for convergence
tol = 1e-6;
% maximum number of iteration
n_iter_max = 200;

% Load faces dataset
load img_faces
img_identity = img_faces.identity;
img_pose = img_faces.pose;
img_expression = img_faces.expression;
img_eye = img_faces.eye;
img = img_faces.data;

% Load extracted features
load feat_pca
load feat_gabor
load feat_hog
load feat_fft

% Compute identity assignment matrix
identity_unique = unique(img_identity);
Y = zeros(length(img_identity),length(identity_unique));
for i = 1:length(img_identity)
   Y(i,img_identity(i)) = 1;
end
aff_Y = Y*Y';
deg_Y = diag(sum(aff_Y).^(-0.5));
aff_Y_norm = deg_Y*aff_Y*deg_Y;

% Compute similarity matrix from original data
kk = floor(log2(length(img_identity)))+1;
% Raw data
D = dist2(img,img);
aff_raw = scale_dist3(D,nn);
deg_raw = diag(sum(aff_raw).^(-0.5));
aff_raw_norm = deg_raw*aff_raw*deg_raw;
% PCA features
D = dist2(feat_pca,feat_pca);
aff_pca = scale_dist3(D,nn);
deg_pca = diag(sum(aff_pca).^(-0.5));
aff_pca_norm = deg_pca*aff_pca*deg_pca;
% gabor features
D = dist2(feat_gabor,feat_gabor);
aff_gabor = scale_dist3(D,nn);
deg_gabor = diag(sum(aff_gabor).^(-0.5));
aff_gabor_norm = deg_gabor*aff_gabor*deg_gabor;
% HoG features
D = dist2(feat_hog,feat_hog);
aff_hog = scale_dist3(D,nn);
deg_hog = diag(sum(aff_hog).^(-0.5));
aff_hog_norm = deg_hog*aff_hog*deg_hog;
% FFT features
D = dist2(feat_fft,feat_fft);
aff_fft = scale_dist3(D,nn);
deg_fft = diag(sum(aff_fft).^(-0.5));
aff_fft_norm = deg_fft*aff_fft*deg_fft;

% Define M sources
%affs = {aff_raw_norm,aff_pca_norm,aff_gabor_norm,aff_hog_norm};
affs = {aff_gabor_norm,aff_fft_norm};
n_sources = length(affs);
[n_instances,~] = size(aff_raw);
% Compute dependency between sources
Q = zeros(n_sources);
for i = 1:n_sources
    for j = i:n_sources
        Q(i,j) = trace(affs{i}*affs{j});
        Q(j,i) = Q(i,j);
    end
end
   
nmi_pose = zeros(length(v_lambda_range),1);
for v_lambda_idx = 1:length(v_lambda_range)
    v_lambda = v_lambda_range(v_lambda_idx);
    % Initialization of res and res_old
    res = 2;
    res_old = 1;
    % Initialization of low-dimensional representation
    U = rand(n_instances,dim_q);
    % Initialization of weights
    beta = ones(n_sources,1)/n_sources;
    % Count the number of loops
    n_iter = 0;
    while abs(res-res_old)/res_old>tol & n_iter<n_iter_max
        U_old = U;
        % Convex combination of kernels of M sources
        aff = zeros(n_instances);
        for i = 1:n_sources
            aff = aff+beta(i)*affs{i};
        end
        % Find U by Newton like algorithm
        run_symnmf = 1;
        H_list = {};
        iter_list = zeros(run_symnmf,1);
        obj_list = zeros(run_symnmf,1);
        for i = 1:run_symnmf
            [H_list{i},iter_list(i),obj_list(i)] = symnmf_newton(aff-...
                v_lambda/2*aff_Y_norm,4);
        end
        for i = 1:run_symnmf
            if obj_list(i) == min(obj_list)
                U = H_list{i};
            break
            end
        end
        % Find beta by Quadratic Programming
        beta_old = beta;
        gamma = zeros(n_sources,1);
        for i = 1:n_sources
            gamma(i) = trace(affs{i}*U*U');
        end
        G = -eye(n_sources);
        h = zeros(n_sources,1);
        A = ones(1,n_sources);
        b = ones(1);
        % Use active set algorithm
        opts = optimoptions('quadprog','Algorithm','active-set','Display','off');
        beta = quadprog(2*Q,-2*gamma,G,h,A,b,[],[],[],opts);
        aff_old = zeros(n_instances);
        for i = 1:n_sources
            aff_old = aff_old+beta_old(i)*affs{i};
        end
        % Compute residue
        res_old = norm(aff_old-U_old*U_old');
        res = norm(aff-U*U');
        n_iter = n_iter+1;
    end
    label_pred = zeros(length(img_pose),1);
    for i = 1:length(img_pose)
        for j = 1:length(unique(img_pose))
            if U(i,j) == max(U(i,:))
                label_pred(i) = j;
            end
        end
    end
    nmi_pose(v_lambda_idx) = nmi(label_pred,img_pose);
    v_lambda_range(v_lambda_idx)
end

plot(v_lambda_range,nmi_pose);
