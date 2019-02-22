
<!-- README.md is generated from README.Rmd. Please edit that file -->
proDD
=====

Differential Detection for Label-free (LFQ) Mass Spectometry Data

The tool fits a probabilistic dropout model to an intensity matrix from from label-free quantification (LFQ). Dropouts in LFQ data occur if the protein has a low intensity. Our model takes the non-random missingness into account, by constructing a Bayesian hierarchical model. After fitting the model you can sample from the posterior distribution of the means from each protein and condition. The posterior are a useful element to calculate all kind of statistics/metrics including the probability that the intensity of a protein in one condition is smaller than in the control (similar to the one-sided p-value).

Installation
============

Install the latest version directly from GitHub (make sure that `devtools` is installed)

``` r
devtools::install_github("const-ae/proDD")
```

Disclaimer
==========

I am still actively working on the project and although the algorithm is working fine at this point, the API might still be subject to change.

Walkthrough
===========

In the following section I will explain how to use the `proDD` package to identify differential detected protein in label-free mass spectrometry data. I will highlight all the important functions the package provides.

At first we have to load the `proDD` package and some additional packages that we will use to plot our data.

``` r
# My package
library(proDD)

# Packages for plotting
library(ggplot2)
library(pheatmap)
library(viridisLite)
set.seed(1)
```

Next we will load some data. To make our life easier we will use synthetic data, where we know which proteins have changed and which have not. For this we will use the `generate_synthetic_data()`. We define that 10% of the protein differ between condtion A and B.

``` r

# The experimental_design is a vector that assignes each sample to one condition
experimental_design <- c("A", "A", "A", "B", "B", "B")

# The generate_synthetic_data can be customized a lot, but here we will 
# use it in its most basic form
syn_data <- generate_synthetic_data(n_rows=1234, experimental_design=experimental_design,
                                    frac_changed = 0.1)

# The data matrix, where non-observed values are coded as NA
X <- syn_data$X

# Median normalization to remove sample effects 
X <- median_normalization(X)

# The columns are the samples and each row is a protein
head(X)
#>                A-1      A-2      A-3      B-1      B-2      B-3
#> protein_1 26.01094 26.19299 24.33803 25.16535 26.44060 25.78596
#> protein_2 21.31483 21.03314 20.82363 22.09844 21.63262 21.11544
#> protein_3 22.07034 21.81571 22.03286 21.88494 22.54004 22.00399
#> protein_4 27.27377 26.87917 27.16113 26.33441 27.61880 26.83838
#> protein_5 17.94104 17.67325 17.68878 17.73461 17.94897       NA
#> protein_6 24.15618 24.13457 24.80671 24.96692 24.83832 23.41206
```

To get a better impression of the raw data we will make a heatmap plot (using the `pheatmap` package). Unfortunately the `hclust` method that is internally used does not support missing values, so we will for this plot just replace all missing values with a zero

``` r
X_for_plotting <- X
X_for_plotting[is.na(X_for_plotting)] <- 0
pheatmap(X_for_plotting,
         main=paste0(round(sum(is.na(X))/prod(dim(X)) * 100), "% missing values"),
         annotation_row = data.frame(changed=as.character(syn_data$changed),
                                     row.names = rownames(X_for_plotting)),
         show_rownames = FALSE)
```

<img src="man/figures/README-unnamed-chunk-4-1.png" width="80%" style="display: block; margin: auto;" />

One important observation is that the missing values do not occur randomly, but predominantly at low intensities. This can be most clearly be seen, when looking at proteins which have some observed and some missing values

``` r
hist_tmp_data <- data.frame(intensity=c(X), 
           row_has_missing=c(t(apply(X, 1, function(x) rep(any(is.na(x)), ncol(X))))))

ggplot(hist_tmp_data, aes(x=intensity, fill=row_has_missing)) +
    geom_histogram() +
    xlim(12, 32)
#> `stat_bin()` using `bins = 30`. Pick better value with `binwidth`.
#> Warning: Removed 1851 rows containing non-finite values (stat_bin).
#> Warning: Removed 4 rows containing missing values (geom_bar).
```

<img src="man/figures/README-unnamed-chunk-5-1.png" width="80%" style="display: block; margin: auto;" />

We conclude from this that there is a certain dropout probability associated with each latent intensity. At low intensities (e.g. `<15`) it is almost certain that the values dropout, whereas for high intensities (e.g. `>25`) almost no value is missing. We capture this idea using a sigmoidal shaped dropout curve that looks roughly like this:

``` r
dropout_curve <- data.frame(intensity=seq(12, 32, length.out=1001))
dropout_curve$dropout_probability <- invprobit(dropout_curve$intensity, rho=18, zeta=-2.5)

ggplot(hist_tmp_data, aes(x=intensity)) +
    geom_histogram(aes(fill=row_has_missing)) +
    geom_line(data=dropout_curve, aes(y=dropout_probability * 600), color="red") +
    xlim(12, 32)
#> `stat_bin()` using `bins = 30`. Pick better value with `binwidth`.
#> Warning: Removed 1851 rows containing non-finite values (stat_bin).
#> Warning: Removed 4 rows containing missing values (geom_bar).
```

<img src="man/figures/README-unnamed-chunk-6-1.png" width="80%" style="display: block; margin: auto;" />

Our probabilistic dropout algorithm has two major steps. In the first step we infer important hyper-parameters of the model using an EM algorithm. The hyper-parameters that we identify are

-   the location and scale of the dropout curve for each sample (called `rho` and `zeta`)
-   the overal location of the values (`mu0` and `sigma20`)
-   a prior for the protein variances (`nu` and `eta`).

``` r
# To see the progress while fitting set verbose=TRUE
params <- fit_parameters(X, experimental_design)
params
#>  Parameters of the probabilistic dropout model
#> 
#> There were 6 samples in 2 conditons. In total there were 1234 rows.
#> The model has successfully converged.
#> The error of the last iteration was 0.0001249
#> 
#> The inferred parameters are:
#> eta:      0.302
#> nu:       3.09
#> mu0:      20.3
#> sigma20:  8.47
#> rho:      18.1, 18.1, 18, 18.1, 18.1, 18
#> zeta:     -1.08, -1.16, -1.06, -1.06, -0.965, -1.08
```

As we can see the method has successfully converged so we can continue. If it would not have converged increase `max_iter`. In this example we are working on a moderately sized data set, usually a thousand proteins are enough to make good estimates of the hyper-parameters, if your dataset has many proteins you can easily speed up the inference by setting for example `n_subsample=1000`.

Knowing the general distribution of our data, we might be interested how the samples are related. Naively we would just calculate the distance matrix using `dist(t(X))`. But `dist` simply scales up vectors containing missing values, which is equivalent to some kind of mean imputation, which does not really make sense as we have seen when we looked where missing values actually occur.

``` r
naive_dist <- dist(t(X))
pheatmap(as.matrix(naive_dist), cluster_rows=FALSE, cluster_cols = FALSE,
         color=viridisLite::plasma(n=100, direction=-1),
         breaks = seq(30, 60, length.out=101),
         display_numbers=round(as.matrix(naive_dist)),
         number_color = "black")
```

<img src="man/figures/README-unnamed-chunk-8-1.png" width="50%" style="display: block; margin: auto;" />

Instead our package provides a function called `dist_approx` that estimates the distances and properly takes into account the missing values. But due to the missing values we cannot be certain of the exact distance. Thus the function returns in addition to the best guess of the distance an estimate how variable that guess is.

``` r
# Removing condtion information to get unbiased results
dist_proDD <- dist_approx(X, params, by_sample=TRUE, blind=TRUE)
# The mean and standard deviation of the sample distance estimates
pheatmap(as.matrix(dist_proDD$mean), cluster_rows=FALSE, cluster_cols=FALSE,
         color=viridisLite::plasma(n=100, direction=-1),
         breaks = seq(30, 60, length.out=101),
         display_numbers=matrix(paste0(round(as.matrix(dist_proDD$mean)), " ± ",
                              round(sqrt(as.matrix(dist_proDD$var)), 1)), nrow=6),
         number_color = "black")
```

<img src="man/figures/README-unnamed-chunk-9-1.png" width="50%" style="display: block; margin: auto;" />

After making sure that there are no extreme outliers in our data and the heatmap shows the group structure that we expected, we will continue to infer the posterior distribution of the mean for each protein and condition.

Those posterior distribution form the basis of the subsequent steps for identifying differentially detected proteins.

``` r
# Internally this function uses Stan to sample the posteriors.
# Stan provides a lot of output which you can see by setting verbose=TRUE
posteriors <- sample_protein_means(X, params, verbose=FALSE)
#> Warning: There were 1 transitions after warmup that exceeded the maximum treedepth. Increase max_treedepth above 10. See
#> http://mc-stan.org/misc/warnings.html#maximum-treedepth-exceeded
#> Warning: Examine the pairs() plot to diagnose sampling problems
```

Now that we have a good idea what is the latent intensity of each protein we can go on to identify the differentially detected proteins

``` r
result <- test_diff(posteriors$A,  posteriors$B)

# The resulting data.frame
head(result)
#>                name      pval  adj_pval         diff diff_quantile_0.025
#> protein_1 protein_1 0.6785740 0.9999580 -0.291432032          -1.7291496
#> protein_2 protein_2 0.1861635 0.8323397 -0.549142724          -1.3593799
#> protein_3 protein_3 0.6433710 0.9999580 -0.172165835          -0.9487982
#> protein_4 protein_4 0.7251470 0.9999580  0.157035095          -0.7953129
#> protein_5 protein_5 0.9738545 0.9999580 -0.003906608          -0.8030738
#> protein_6 protein_6 0.9511200 0.9999580 -0.033457791          -1.1671860
#>           diff_quantile_0.975     mean
#> protein_1           1.0978970 25.49918
#> protein_2           0.3792725 21.33087
#> protein_3           0.5618499 22.03837
#> protein_4           1.1028073 26.92054
#> protein_5           0.9195002 17.79907
#> protein_6           1.0369523 24.30052

# The most significant changes
head(result[order(result$pval), ])
#>                      name  pval     adj_pval     diff diff_quantile_0.025
#> protein_1120 protein_1120 5e-07 2.285185e-05 2.635568            1.773760
#> protein_1123 protein_1123 5e-07 2.285185e-05 3.740655            2.847882
#> protein_1136 protein_1136 5e-07 2.285185e-05 6.508895            4.018305
#> protein_1150 protein_1150 5e-07 2.285185e-05 3.752084            3.027714
#> protein_1151 protein_1151 5e-07 2.285185e-05 8.752962            7.712919
#> protein_1153 protein_1153 5e-07 2.285185e-05 8.657540            6.771016
#>              diff_quantile_0.975     mean
#> protein_1120            3.483684 20.99344
#> protein_1123            4.541386 21.58175
#> protein_1136           10.293318 19.11484
#> protein_1150            4.504923 23.32864
#> protein_1151            9.958242 21.75045
#> protein_1153           10.427010 21.35123
```

A popular way to look at such data is to make a volcano plot. Here we will use the fact that we generated the data to highlight proteins that were actually changed

``` r
result$changed <- syn_data$changed

ggplot(result, aes(x=diff, y=-log10(pval), color=changed)) +
    geom_point() +
    ggtitle("Volcano plot highlighting truely changed values")
```

<img src="man/figures/README-unnamed-chunk-12-1.png" width="80%" style="display: block; margin: auto;" />

We know that 10% of the data was changed and in the volcano plot we can see that our method does a good job of identifying many of them.

An interesting way to look at at the data is to explicitly look how many values were observed per condition. So we will make 16 plots, where we compare the difference between for A and B if we had three 3 vs. 3, 3 vs. 2, 3 vs. 1 etc. observed values.

``` r
result$nobs_a <- rowSums(! is.na(X[, experimental_design == "A"]))
result$nobs_b <- rowSums(! is.na(X[, experimental_design == "B"]))

ggplot(result, aes(x=diff, y=-log10(pval), color=changed)) +
    geom_point() +
    facet_grid(nobs_a ~ nobs_b, labeller = label_both)
```

<img src="man/figures/README-unnamed-chunk-13-1.png" width="80%" style="display: block; margin: auto;" />

Using this data we can also make an MA plot, where we color the points by the number of observations

``` r
result$label <- paste0(pmax(result$nobs_a, result$nobs_b), "-", pmin(result$nobs_a, result$nobs_b))

ggplot(result, aes(x=mean, y=diff, color=label, shape=changed)) +
    geom_point(size=2) +
    ggtitle("MA plot comparing the number of observed values")
```

<img src="man/figures/README-unnamed-chunk-14-1.png" width="80%" style="display: block; margin: auto;" />

``` r

ggplot(result, aes(x=mean, y=diff, color=adj_pval < 0.05)) +
    geom_point(size=2) +
    ggtitle("MA plot identifying significant and non-significant values")
```

<img src="man/figures/README-unnamed-chunk-14-2.png" width="80%" style="display: block; margin: auto;" />
