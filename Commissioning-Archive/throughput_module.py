'''
throughput_module.py
Updated: 6/23/2025

This file contains the functions needed to run throughput measurements with the DRRP

Although not completely generalized, users should be able to replace a few key structures within these functions 
so that they can work with fits files with names of any format

Alternatively, following the naming conventions outlined in the Throughput_Notebook.ipynb file will let 
these functionsbe used more or less as they are
'''

############################## Imports ################################

import numpy as np
import matplotlib.pyplot as plt
from scipy.interpolate import interp1d
import glob
import os
from astropy.io import fits
from scipy.ndimage import center_of_mass
import shutil as su

#######################################################################
def splice_data(directory, file_name, ranges, scrap_savepath):
    '''
    splices out the wrapped images from a data cube in the JHK waveplate data set
    in:
        directory - all the way down to the position...ie h6_v4
        file_name - name of the file to splice, all the way down to .fits
        ranges - range of files to keep
        scrap_savepath - wherever we want to keep the original file
    out:
        returns - none
        files - renames the original file and saves it to scrap_savepath...this should end with '_scrap'
    '''   

    path = directory + '\\' + file_name + '.fits'

    with fits.open(path) as hdul:

        # initialize the data cube
        data_cube = np.asarray(hdul[0].data.copy())
        print(type(data_cube))

        # initialize the pwr list
        hdr = hdul[0].header.copy()
        pwr_list = np.asarray(hdr['OPMPOWER'][1:-1].split(',')).astype(float)

        # use the ranges to chop up the pwr_list and data_cube
        indices = np.r_[tuple(slice(start,stop) for start,stop in ranges)]
            
        pwr_list_splice = pwr_list[indices]

        # make sure these are strings that can be read in to a header
        pwr_list_splice = '[' + ', '.join(f'{x:.8e}' for x in pwr_list_splice) + ']'

        data_cube_splice = data_cube[indices,:,:]
        

    # move the original file to the scrap_savepath
    su.move(path,scrap_savepath)

    # make a new file in the normal data directory containing the spliced data_cube and pwr_list
    hdu2 = fits.PrimaryHDU(data=data_cube_splice)
    hdu2.writeto(path)

    with fits.open(path, mode='update') as hdul:
        hdr = hdul[0].header
        hdr['OPMPOWER'] = pwr_list_splice

    print('done')

####################################################################################################################

def dark_subtract_2(directory,wvls):
    '''
    This version of dark_subtract goes before the normalization using the photodiode measurements...
    It performs pixel - by -pixe dark subtraction on the air and position measurements in the throughput data set
    in:
        directory (str) - greater directory containing the throughput data set
        wvls (list of str) - wavelengths used in the experiment 

    out:    
        fits files - they will have the same name as the originals with _dsub attached to the end...
            they will be placed in the same folder as the originals 
    '''

    for wvl in wvls:

        # create the pattern for the files we want...these should be the base files...use glob.glob to get 
        #   a list of file names
        pattern = os.path.join(directory,'**','*'+wvl+'*.fits')
        file_list = glob.glob(pattern, recursive = True)

        # predefine lists that will hold filenames for ach type of file
        pos_list = []
        air_list = []
        drk_list = []

        # put the file names into the lists 
        for f in file_list:

            #check if it's an aircal file
            if 'Air' in f:
                air_list.append(f)
            #check if it's a dark
            elif 'Dark' in f:
                drk_list.append(f)
            #if neither of the above, it must be a positional measurement 
            else:
                pos_list.append(f)

        # check if there is more than one dark frame; throw an error if there is
        if len(drk_list) > 1:
            print('More than one dark frame detected for wvl: '+ str(wvl))
            return False
        
        # same check for the air calibtration files
        if len(air_list) > 1:
            print('More than one air_cal frame detected for wvl: '+ str(wvl))
            return False        
        
        # create the dark frame...first, access the fits file
        f_drk = drk_list[0]
        with fits.open(f_drk) as hdul:
            drk_cube = np.asarray(hdul[0].data)

        # median over the 0 axis
        drk_med = np.median(drk_cube, axis = 0)

        # access each measurement and air_cal file...subtract the drk_med from each individual frame...
        #   note that we need to keep the OPMPOWER header, so we also take take that out to put into the new file

        # first the air_cal file

        # access the file, nab the data cube and header
        with fits.open(air_list[0]) as hdul:
            air_cube = np.asarray(hdul[0].data)
            hdr = hdul[0].header


        # dark subtract the air, save a fits file
        air_dsub = air_cube - drk_med

        fname = air_list[0].split("\\")[-1].split('.f')[0]
        path = air_list[0].split("\\Air_Meas")[0]
        hdu2 = fits.PrimaryHDU(data=air_dsub, header = hdr)
        write_path = path+"\\"+fname+"_dsub.fits"
        hdu2.writeto(write_path)
        print('dark subtracted file saved to '+path+"\\"+fname+"_dsub.fits")
            
        # do the same for the measurement files
        for i in range(len(pos_list)):
            
            # access the file, nab the data cube and header
            with fits.open(pos_list[i]) as hdul:
                pos_cube = np.asarray(hdul[0].data)
                hdr = hdul[0].header

            # subtract the drk_med from pos_cube, save a fit file
            pos_cube_dsub = pos_cube - drk_med

            fname = pos_list[i].split("\\")[-1].split('.f')[0]
            path = pos_list[i].split("\\D")[0]
            write_path = path+"\\"+fname+"_dsub.fits"
            hdu2 = fits.PrimaryHDU(data=pos_cube_dsub, header = hdr)
            hdu2.writeto(write_path)
            print('dark subtracted file saved to '+path+"\\"+fname+"_dsub.fits")

####################################################################################################################

def normalize_photodiode_readings_aircal_2(directory, wvls):
    """Reads in all the .fits files, normalizes by air_cal, such that the air_cal photodiode reading for each
            wavelength is always 1, and the photodiode readings for the waveplate measurements give the percentage of 
            the power relative to the air_cal. It divides (pixel - by - pixel) each median frame by the normalized
            photodiode reading for that wavelength. It then writes the normalized data to a new fits files ending with 
            'dsub_norm.fits'.

        ins:
            directory (str) - string for directory containing all subfolders of data
            wvls (list) - list containing STRINGS for each wavelength (or other identifiable parameter for looping...
                ***THIS MUST BE A LIST***

        outs:
            fits files - 'dsub_norm.fits' containing the normalized median frame + previous headers and the 
                normalized photodiode reading as a header 'NORMPWR'
    """

    ##step 1: get the median power reading for each file; sepearate them into air cals and wp meas 

    for wvl in wvls:

        pattern = os.path.join(directory,'**','*'+wvl+'*dsub.fits')
        #print("Pattern: " + str(pattern))
        file_list = glob.glob(pattern, recursive = True)
        # we need to separate airs from wp meas
        pwr_list = []
        air_pwr_list = []

        for f in file_list:
            if 'Air' in f:
                hdul = fits.open(f)
                hdr = hdul[0].header
                try:
                    pwr = np.asarray(hdr['OPMPOWER'][1:-1].split(',')).astype(float)
                    median_pwr = np.median(pwr)
                    air_pwr_list.append(median_pwr)
                except:
                    print("this is probably a dark frame, keyword OPMPOWER not found")
                    pwr_list.append(np.nan)
            
            else:
                hdul = fits.open(f)
                hdr = hdul[0].header
                try:
                    pwr = np.asarray(hdr['OPMPOWER'][1:-1].split(',')).astype(float)
                    median_pwr = np.median(pwr)
                    pwr_list.append(median_pwr)
                except:
                    print("this is probably a dark frame, keyword OPMPOWER not found")
                    pwr_list.append(np.nan)

        ## step 2: normalize based on the average aircal reading

        # find the median aircal meas
        air_cal_med = np.median(air_pwr_list) 
        num_cals = len(air_pwr_list)

        # divide all median power reading by that number such that we get the % above/below the aircal   
        air_pwr_list_norm = air_pwr_list / air_cal_med
        pwr_list_norm = pwr_list / air_cal_med

        # put these into one list for ease of use

        norm_pwr_list = np.concatenate((air_pwr_list_norm,pwr_list_norm))
        print(norm_pwr_list)

        ## step 3: write these normalized jawns back to the headers

        for i in range(len(file_list)):
                hdul = fits.open(file_list[i])
                hdr = hdul[0].header

                if np.isnan(norm_pwr_list[i])==False:
                    normpwr = norm_pwr_list[i]
                    hdr['NORMPWR'] = normpwr

                    ##median collapse cube
                    data = np.median(hdul[0].data,axis=0)
                    #normalized
                    norm_data = data/normpwr

                    if 'Dark' in file_list[i]:
                        print('dark frame...do nothing')

                    elif i < num_cals:
                        fname = file_list[i].split("\\")[-1].split('.f')[0]
                        path = file_list[i].split("\\Air_Meas")[0]
                        hdu2 = fits.PrimaryHDU(data=norm_data,header=hdr)
                        write_path = path+"\\"+fname+"_norm.fits"
                        hdu2.writeto(write_path)
                        print('normalized file saved to '+path+"\\"+fname+"_norm.fits")

                    elif i >= num_cals:
                        fname = file_list[i].split("\\")[-1].split('.f')[0]
                        path = file_list[i].split("\\D")[0]
                        hdu2 = fits.PrimaryHDU(data=norm_data,header=hdr)
                        write_path = path+"\\"+fname+"_norm.fits"
                        hdu2.writeto(write_path)
                        print('normalized file saved to '+path+"\\"+fname+"_norm.fits")

                else:
                    "not saving a normalized file, this is probably a dark"
                    pass

#####################################################################################################################

def mod_centroid(im, threshold):
    '''
    takes an image, converts it to a binary image based on a threshold, then finds the centroid of the image...
        this is necessary because the beam is not always centered on the same spot on the detector, and the measured 
        intensity varies spatially over the image...put simply, we care about the center of teh image, not the weighted
        'center of mass'
    
    in:
        im - preferrably a numpy array
        threshold - value in counts 
    out:
        centroid - [y,x] coordinates of the centroid of the image
    '''

    # make the mask based on the threshold 
    mask = im > threshold
    mask[mask>0]=1  # convert to binary mask

    # apply centroiding to the mask 
    com = center_of_mass(mask)

    # com is a tuple of (y, x) coordinates
    return com

def aperture_sum(im, com, radius):
    '''
    Takes an image, a center, and a radius, then sums the counts within that radius of the center

    in:
        im - numpy array of the image
        com - [y,x] coordinates of the centroid (given by mod_centroid)
        radius - radius in pixels to sum over

    out:
        total_counts - total counts within the aperture
    '''

    # get the shape of the image
    y_size, x_size = im.shape

    # create a grid of coordinates
    y_indices, x_indices = np.indices((y_size, x_size))

    # calculate the distance from the centroid
    distances = np.sqrt((y_indices - com[0])**2 + (x_indices - com[1])**2)

    # create a mask for pixels within the radius
    mask = distances <= radius

    # sum the counts within the aperture
    total_counts = np.sum(im[mask])

    return total_counts

def get_throughput(directory, wvls, threshold, radius):
    '''
    Takes the normalized, dark subtracted air_cal and pos_meas files and calcultes the throughput by summing the counts
    within a certain radius of the centroid of the beam on the detector within the aperture radius, then dividing
    by the air_cal counts within the same radius.

    in:
        directory (str) - directory containing the dark subtracted air_cal and pos_meas files
        wvls (list of str) - list of wavelengths for the measurements, each index must be a string
        radius (int) - radius in pixels for the aperture summing
    
    out:
        THRUPUT (Header) - THRUPUT keyword is added as a header to the '_dsub_norm.fits' files 
    '''

    #define the wavelength:
    for wvl in wvls:

    ## step 1: we want to identify the air_cal and pos_meas file names for each wvl
        pattern = os.path.join(directory,'**','*'+ wvl +'*dsub_norm.fits')
        file_list = glob.glob(pattern, recursive = True)
        print(file_list)
        # predefine lists of each file type
        pos_list = []
        air_list = []

        for f in file_list:

            #check if it's an aircal file
            if 'Air' in f:
                air_list.append(f)

            #if not aircal, it must be a positional measurement 
            else:
                pos_list.append(f)

    
    ## Step 2: define the aircal, centroid it, and then aperture sum

        # define the air_cal
        hdul_a = fits.open(air_list[0])
        air = hdul_a[0].data
        air = np.array(air)

        # centroid the air_cal
        air_com = mod_centroid(air, threshold)

        # sum counts in the aircal
        air_sum = aperture_sum(air, air_com, radius)

    ## Step 3: loop through the positional measurements, centroid them, aperture sum, and calculate throughput...
        # we'll also add the throughput (as a fraction of the aircal counts) to the dark subtracted fits file
        # as a header

        # loop
        for i in range(len(pos_list)):
            # open the measurement file
            hdul_p = fits.open(pos_list[i])
            pos = hdul_p[0].data
            pos = np.array(pos)

            # centroid the image
            pos_com = mod_centroid(pos, threshold)

            # sum counts in aperture
            pos_sum = aperture_sum(pos, pos_com, radius)

            # calculate thruoghput
            throughput = pos_sum / air_sum

            # add throughput to the header of the dark subtracted file
            with fits.open(pos_list[i], mode='update') as hdul_p:
                hdr_p = hdul_p[0].header
                hdr_p['THRUPUT'] = throughput
                print(throughput)

        print('finished with wavelength: ' + wvl)

######################################################################################################################

def throughput_readout(directory, wvl):
    '''
    Takes thruput values from '...norm_dsub.fit' files and plots the throughputs as a function of wavelength 

    ***takes a single wavelength as a string, not a list of wavelengths***
    '''

    # define list of filenames 
    pattern = os.path.join(directory,'**','*'+ wvl +'*dsub_norm.fits')
    file_list = glob.glob(pattern, recursive = True)

    # predefine list for files with wavlength of wvl
    meas_list = []

    # loop through the files and append the thruput values to the list
    for f in file_list:
        if 'Air' not in f:
            meas_list.append(f)
        
    # we now have a list of filenames that will contain thruput measurements...
        
    # predefine a list that will contain the throughput values
    thruput_list = []

    # loop through the files...open, read header, append header to list
    for f in meas_list:
        with fits.open(f) as hdul:
            hdr = hdul[0].header
            try:
                thruput = hdr['THRUPUT']
                thruput_list.append(float(thruput))
            except KeyError:
                print('THRUPUT keyword not found in header of file: ' + f)

    # convert the wvl to a float
    wavelength = float(wvl)

    # return the thruput_list and the wavelength as a tuple
    return thruput_list, wavelength 


def plot_thruput(directory, wvls):
    '''
    uses get_thruput to create a plot of the average throughput as a function of wavelength...
    error bars are one standard deviation

    in:
        directory (str) - location of all the measurements
        wvls (str) - list of strings containing wavelengths for each measurement
    '''

    # initialize a list for averages, stds, and integer wavelengths
    avg_thruput_list = []
    std_list = []
    wvls_int = []

    # loop through the wavelengths...use get_throughputs, then avg and find std
    for wvl in wvls:

        # get thruputs and wvls using throughput_readout
        thruput_list, wavelength = throughput_readout(directory, wvl)

        # append the integer wavelength to the list
        wvls_int.append(wavelength)

        # find the average of the wavelength...append
        avg_thruput = np.mean(thruput_list)
        avg_thruput_list.append(avg_thruput)

        # find the standard deviation of the thruputs...this will become an error bar...append 
        std = np.std(thruput_list)
        std_list.append(std)

    # plot with errorbars 
    plt.errorbar(wvls_int, avg_thruput_list, yerr=std_list, fmt='o', capsize=5, label='Average Throughput')
    plt.xlabel('Wavelength (nm)')
    plt.ylabel('Throughput (fraction of Air Calibration)')
    plt.title('JHK Waveplate Throughput by Wavelength')
    plt.grid(which = 'major', color = 'gray', linestyle = '-', linewidth = 0.5)
    plt.grid(which = 'minor', color = 'lightgray', linestyle = '-', linewidth = 0.5)
    plt.show()
    
def plot_wavelength(directory, wvl, pos_list = ['h3_v1', 'h3_v2', 'h3_v3', 'h3_v4', 'h3_v5', 'h3_v6', 'h4_v1', 'h4_v2', 'h4_v3', 'h4_v4', 'h4_v5', 'h4_v6', 'h5_v1', 'h5_v2', 'h5_v3', 'h5_v4', 'h5_v5', 'h5_v6', 'h6_v1', 'h6_v2', 'h6_v3', 'h6_v4', 'h6_v5', 'h6_v6', 'h6_vt4']):
    '''
    plots all the thruput measurements taken at a given wavelength...x axis will be the 
        position of the moving base
    '''

    # define the patern for the files
    pattern = os.path.join(directory,'**','*'+ wvl +'*dsub_norm.fits')
    file_list = glob.glob(pattern, recursive = True)

    # readout the thruput measurements from each file...initiate a list first though
    thruput_list = []

    for f in file_list:
        if 'Air' not in f:
            with fits.open(f) as hdul:
                hdr = hdul[0].header
                try:
                    thruput = hdr['THRUPUT']
                    thruput_list.append(float(thruput))
                except KeyError:
                    print('THRUPUT keyword not found in header of file: ' + f)

    # create a scatterplot with thruput on y and pos_list on x
    plt.figure(figsize=(10, 6))
    plt.scatter(pos_list, thruput_list, color='blue', label='Throughput Measurements')
    plt.xticks(rotation=45)
    plt.xlabel('Position on Moving Base')
    plt.ylabel('Throughput (fraction of Air Calibration)')
    plt.title(f'Throughput Measurements at {wvl} nm')
    plt.grid(which='major', color='gray', linestyle='-', linewidth=0.5)
    plt.grid(which='minor', color='lightgray', linestyle='-', linewidth=0.5)
    plt.show()
