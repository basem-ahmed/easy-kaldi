#!/bin/bash

# Easy Kaldi // Josh Meyer (2018) // jrmeyer.github.io
#
# based on the multi-lingual babel scripts from Pegah Ghahremani

# REQUIRED:
#
#    (1) baseline PLP features, and models (tri or mono) alignment (e.g. tri_ali or mono_ali)
#        for all tasks
#    (2) input data (audio, lm, etc)
#
# This script can be used for training multi-task setup using different
# tasks with no shared phones.
#
# It will generate separate egs directory for each dataset and combine them
# during training.
#
# In the multi-task training setup, mini-batches of data corresponding to
# different tasks are randomly combined to generate egs.*.scp files
# using steps/nnet3/multilingual/combine_egs.sh and generated egs.*.scp files
#
# For all tasks, we share all except last hidden layer and there is separate final
# layer per task.
#
# This script does not use ivectors or bottleneck feats
#
#







### STAGES
##
#

config_nnet=1
make_egs=1
combine_egs=1
train_nnet=1
make_copies_nnet=1
decode_test=1

#
##
###

set -e


. ./path.sh
. ./utils/parse_options.sh


your_corpus=$1   # char string of input_dir name
hidden_dim=$4  # number of hidden dimensions in NNET
num_epochs=$5  # number of epochs through data
main_dir=$6    # location of /data and /exp dir (probably "MTL")



cmd="utils/run.pl"

exp_dir=$main_dir/exp/nnet3/easy
master_egs_dir=$exp_dir/egs





if [ 1 ]; then

    #########################################
    ### SET VARIABLE NAMES AND PRINT INFO ###
    #########################################
    
    # Check data files
    for f in $main_dir/data/$your_corpus/train/{feats.scp,text} \
	     $main_dir/exp/$your_corpus/tri_ali/ali.1.gz \
	     $main_dir/exp/$your_corpus/tri_ali/tree; do
        [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
        done
    done
    
    # Make dirs for your corpus
    data_dir=$main_dir/data/$your_corpus/train
    egs_dir=$main_dir/exp/$your_corpus/nnet3/egs
    ali_dir=$main_dir/exp/$your_corpus/tri_ali
    
    num_targets=`tree-info $ali_dir/tree 2>/dev/null | grep num-pdfs | awk '{print $2}'` || exit 1;
	
        echo ""
        echo "###### BEGIN TASK INFO ######"
        echo "task= $your_corpus"
        echo "num_targets= $num_targets"
        echo "data_dir= $data_dir"
        echo "ali_dir= $ali_dir"
        echo "egs_dir= $egs_dir"
        echo "###### END TASK INFO ######"
        echo ""

    done
fi




if [ "$config_nnet" -eq "1" ]; then

    echo "### ============================ ###";
    echo "### CREATE CONFIG FILES FOR NNET ###";
    echo "### ============================ ###";

    mkdir -p $exp_dir/configs

    feat_dim=`feat-to-dim scp:$data_dir/feats.scp -`
    num_targets=`tree-info $ali_dir/tree 2>/dev/null | grep num-pdfs | awk '{print $2}'` || exit 1;
    hidden_dim=$hidden_dim

    cat <<EOF > $exp_dir/configs/network.xconfig
input dim=$feat_dim name=input
relu-renorm-layer name=tdnn1 input=Append(input@-2,input@-1,input,input@1,input@2) dim=$hidden_dim
relu-renorm-layer name=tdnn2 dim=$hidden_dim
relu-renorm-layer name=tdnn3 input=Append(-1,2) dim=$hidden_dim
relu-renorm-layer name=tdnn4 input=Append(-3,3) dim=$hidden_dim
relu-renorm-layer name=tdnn5 input=Append(-3,3) dim=$hidden_dim
relu-renorm-layer name=tdnn6 input=Append(-3,3) dim=$hidden_dim
relu-renorm-layer name=tdnn7 input=Append(-3,3) dim=$hidden_dim
relu-renorm-layer name=tdnn8 input=Append(-3,3) dim=$hidden_dim
relu-renorm-layer name=tdnn9 input=Append(-3,3) dim=$hidden_dim
relu-renorm-layer name=tdnn10 input=Append(-3,3) dim=$hidden_dim
relu-renorm-layer name=tdnn11 input=Append(-3,3) dim=$hidden_dim
relu-renorm-layer name=tdnnFINAL input=Append(-3,3) dim=$hidden_dim
relu-renorm-layer name=prefinal-affine-layer input=tdnnFINAL dim=$hidden_dim
output-layer name=output dim=$num_targets max-change=1.5	 
EOF
        
    steps/nnet3/xconfig_to_configs.py \
        --xconfig-file $exp_dir/configs/network.xconfig \
        --config-dir $exp_dir/configs/
fi




if [ "$make_egs" -eq "1" ]; then
        
    echo "### =================== ###"
    echo "### MAKE NNET3 EGS DIR  ###"
    echo "### =================== ###"

    steps/nnet3/get_egs.sh \
	--cmd "$cmd" \
	--cmvn-opts "--norm-means=false --norm-vars=false" \
        --left-context 30 \
        --right-context 31 \
	$data_dir \
	$ali_dir \
	$master_egs_dir/egs \
	|| exit 1;

fi



if [ "$train_nnet" -eq "1" ]; then

    echo "### ================ ###"
    echo "### BEGIN TRAIN NNET ###"
    echo "### ================ ###"

    steps/nnet3/train_raw_dnn.py \
        --stage=-5 \
        --cmd="$cmd" \
        --trainer.num-epochs $num_epochs \
        --trainer.optimization.num-jobs-initial=1 \
        --trainer.optimization.num-jobs-final=1 \
        --trainer.optimization.initial-effective-lrate=0.0015 \
        --trainer.optimization.final-effective-lrate=0.00015 \
        --trainer.optimization.minibatch-size=256,128 \
        --trainer.samples-per-iter=10000 \
        --trainer.max-param-change=2.0 \
        --trainer.srand=0 \
        --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
        --feat-dir $data_dir \
        --egs.dir $master_egs_dir \
        --use-dense-targets false \
        --targets-scp $ali_dir \
        --cleanup.remove-egs true \
        --use-gpu true \
        --dir=$exp_dir  \
        || exit 1;
    

    
    # Get training ACC in right format for plotting
    utils/format_accuracy_for_plot.sh "$main_dir/exp/nnet3/easy/log" "ACC_nnet3_easy.txt";


    echo "### ============== ###"
    echo "### END TRAIN NNET ###"
    echo "### ============== ###"

fi




if [ "$make_copies_nnet" -eq "1" ]; then

    echo "### ========================== ###"
    echo "### SPLIT & COPY NNET PER TASK ###"
    echo "### ========================== ###"
    
    task_dir=$exp_dir/$your_corpus
        
    mkdir -p $task_dir
        
    echo "$0: add transition model."
        
    nnet3-copy \
        --edits="rename-node old-name=output-$i new-name=output" \
        $exp_dir/final.raw \
        - | \
        nnet3-am-init \
            $ali_dir/final.mdl \
            - \
            $task_dir/final.mdl \
        || exit 1;
    
    cp $exp_dir/cmvn_opts $task_dir/cmvn_opts || exit 1;
        
    echo "$0: compute average posterior and readjust priors for task $your_corpus."
    
    steps/nnet3/adjust_priors.sh \
        --cmd "$cmd" \
        --use-gpu true \
        --iter "final" \
        --use-raw-nnet false \
        $task_dir \
	$egs_dir \
        || exit 1;
    done
fi





if [ "$decode_test" -eq "1" ]; then

    echo "### ============== ###"
    echo "### BEGIN DECODING ###"
    echo "### ============== ###"

    
    test_data_dir=data_$your_corpus/test
    graph_dir=exp_$your_corpus/triphones/graph
    decode_dir=${exp_dir}/decode
    final_model=${exp_dir}/$your_corpus/final_adj.mdl
    
    mkdir -p $decode_dir

    unknown_phone="SPOKEN_NOISE"
    silence_phone="SIL"

    echo "### decoding with $( `nproc` ) jobs, unigram LM ###"
    
    steps/nnet3/decode.sh \
        --nj `nproc` \
        --cmd $cmd \
        --max-active 250 \
        --min-active 100 \
        $graph_dir \
        $test_data_dir\
        $decode_dir \
        $final_model \
        $unknown_phone \
        $silence_phone \
        | tee $decode_dir/decode.log

    printf "\n#### BEGIN CALCULATE WER ####\n";
 
    for x in ${decode_dir}*; do
        [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh > WER_nnet3_easy.txt;
    done


    echo "hidden_dim=$hidden_dim"  >> WER_nnet3_easy.txt;
    echo "num_epochs=$num_epochs"  >> WER_nnet3_easy.txt;

    echo ""  >> WER_nnet3_easy.txt;

    echo "test_data_dir=$test_data_dir" >> WER_nnet3_easy.txt;
    echo "graph_dir=$graph_dir" >> WER_nnet3_easy.txt;
    echo "decode_dir=$decode_dir" >> WER_nnet3_easy.txt;
    echo "final_model=$final_model" >> WER_nnet3_easy.txt;
    
          
    num_targets=`tree-info $ali_dir/tree 2>/dev/null | grep num-pdfs | awk '{print $2}'` || exit 1;
        
        echo "
    ###### BEGIN EXP INFO ######
    task= $your_corpus
    num_targets= $num_targets
    data_dir= $data_dir
    ali_dir= $ali_dir
    egs_dir= $egs_dir
    ###### END EXP INFO ######
    " >> WER_nnet3_easy.txt;
    done

    echo "###==============###"
    echo "### END DECODING ###"
    echo "###==============###"

fi

