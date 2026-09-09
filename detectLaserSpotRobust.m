function [wCent, area, eDia, xy] = detectLaserSpotRobust(roiImage, minROISize)
% detectLaserSpotRobust: 稳健激光光斑检测，含背景抑制与亚像素质心
% 输入: roiImage    - 单通道灰度图 (double, ROI局部坐标)
%       minROISize  - 动态ROI边长下限(px), 缺省60。可通过App控件调整:
%                     光斑越小可下调, 光斑越大上调, 0则不设下限(慎用)。
% 输出: wCent [x,y] 亚像素质心, area 面积, eDia 等效直径, xy [x1 y1 x2 y2] 新动态ROI
%
% 抗粗糙表面散斑策略（防止ROI正反馈缩小、追到像素级小特征）：
%   1. 较强高斯平滑把散斑颗粒模糊成整体亮区，便于切出整块光斑
%   2. 形态学开/闭/填洞合并光斑内部散斑暗缝，剔除孤立小亮点
%   3. 评分=面积×圆度（在亮度达标候选中），优先选大面积整体光斑，
%      而非旧版"亮度×圆度"所偏好的孤立小散斑亮核
%   4. 动态ROI边长设绝对下限，防止追到小特征时窗口正反馈缩小

    [H, W] = size(roiImage);

    % 动态ROI边长下限(缺省60, 可由App控件传入)。0表示不设下限。
    if nargin < 2 || isempty(minROISize)
        minROISize = 60;
    end

    % ---- 1. 预处理 ----
    % 轻量中值滤波去椒盐噪声
    filtered = medfilt2(roiImage, [3, 3]);

    % Top-Hat 滤波抑制不均匀背景（保留比结构元半径小的亮特征）
    % 半径35约为典型光斑直径的1.5~2倍，可根据实际光斑大小调整
    se = strel('disk', 35);
    bgRemoved = imtophat(filtered, se);

    % 较强高斯平滑（sigma=4，原为2）：粗糙表面激光散斑颗粒尺寸~1px，
    % 平滑后散斑融合为整体亮区，避免二值化切出零散小亮点。
    % 仅用于二值化选blob，亚像素质心在第4步的smoothed上重算，精度不受损。
    smoothed = imgaussfilt(bgRemoved, 4);

    % ---- 2. 二值化（Otsu全局阈值，比adaptive更快更稳定）----
    normImg = rescale(smoothed);
    T = max(graythresh(normImg), 0.25);  % 保底阈值防低对比度误检
    bw = normImg >= T;

    % 形态学整合：开运算去残留孤立散斑；闭运算+填洞把光斑内部
    % 散斑暗缝连成实心块，提升真实光斑的连通性与圆度
    bw = imopen(bw, strel('disk', 2));
    bw = imclose(bw, strel('disk', 5));
    bw = imfill(bw, 'holes');
    bw = bwareaopen(bw, 30);  % 面积下限提高，排除小散斑连通块

    % ---- 3. 候选光斑筛选 ----
    tabBlob = regionprops('table', bw, roiImage, ...
        'Area', 'WeightedCentroid', 'MaxIntensity', 'Circularity', 'EquivDiameter');

    if isempty(tabBlob)
        [wCent, area, eDia, xy] = deal([], [], [], []);
        return;
    end

    % 圆度过滤（排除线状/块状噪声）
    tabBlob = tabBlob(tabBlob.Circularity >= 0.35, :);
    if isempty(tabBlob)
        [wCent, area, eDia, xy] = deal([], [], [], []);
        return;
    end

    % 只保留亮度达标的候选（≥全局最大亮度的50%），排除大块弱背景噪声
    maxInt = max(tabBlob.MaxIntensity);
    tabBlob = tabBlob(tabBlob.MaxIntensity >= 0.5 * maxInt, :);
    if isempty(tabBlob)
        [wCent, area, eDia, xy] = deal([], [], [], []);
        return;
    end

    % 综合评分：面积×圆度。优先选大面积整体光斑，而非小面积高圆度的
    % 孤立散斑亮核。旧版 MaxIntensity*Circularity 同时奖励"高亮+高圆"，
    % 而散斑亮核恰好同时具备这两条，故系统性偏好小亮核——此处以面积
    % 为主导纠正之（真实光斑是连片亮区，面积远大于零散散斑）。
    [~, idx] = max(tabBlob.Area .* tabBlob.Circularity);

    area = tabBlob.Area(idx);
    eDia = tabBlob.EquivDiameter(idx);
    coarseCent = tabBlob.WeightedCentroid(idx, :);

    % ---- 4. 亚像素质心精化 ----
    % 在smoothed（背景已抑制+散斑已模糊）上加权矩，质心稳定在整块光斑
    % 中心，抗散斑拉偏。patch半径设下限12px，保证覆盖整块光斑（含弱
    % 边缘）而非只围着某个小亮核。
    r  = max(ceil(eDia * 1.5), 12);
    cx = round(coarseCent(1));
    cy = round(coarseCent(2));
    px1 = max(1, cx - r);  px2 = min(W, cx + r);
    py1 = max(1, cy - r);  py2 = min(H, cy + r);

    patch = smoothed(py1:py2, px1:px2);
    [gx, gy] = meshgrid(px1:px2, py1:py2);
    ws = sum(patch(:));
    if ws > 0
        wCent = [sum(gx(:) .* patch(:)) / ws, ...
                 sum(gy(:) .* patch(:)) / ws];
    else
        wCent = coarseCent;
    end

    % ---- 5. 动态 ROI（跟踪窗口，供下一帧使用）----
    % margin设下限minROISize：防止检测到小散斑时eDia偏小导致ROI正反馈
    % 缩小、最终追到像素级小特征；上限不超ROI图尺寸。minROISize缺省60，
    % 为典型光斑的合理覆盖，可由App控件按实际光斑大小调整。
    margin = 6 * eDia;
    if minROISize > 0
        margin = max(margin, minROISize);
    end
    margin = min(margin, min(H, W));
    x1 = round(wCent(1) - margin / 2);
    y1 = round(wCent(2) - margin / 2);
    x2 = round(x1 + margin - 1);
    y2 = round(y1 + margin - 1);
    xy = [x1, y1, x2, y2];
end
