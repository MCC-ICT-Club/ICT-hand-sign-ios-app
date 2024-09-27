from PIL import Image


def crop_image(input_image_path, output_image_path):
    # Open an image file
    with Image.open(input_image_path) as img:
        # Define the crop box (left, upper, right, lower)
        # This crops the center of the image
        width, height = img.size
        new_width = 1024
        new_height = 1024

        # Calculate cropping box to be centered
        left = (width - new_width) / 2
        top = (height - new_height) / 2
        right = (width + new_width) / 2
        bottom = (height + new_height) / 2

        # Perform the crop
        # cropped_img = img.crop((left, top, right, bottom))
        cropped_img = img.resize((new_width, new_height))
        # Save the cropped image
        cropped_img.save(output_image_path)
        print(f"Image cropped and saved to {output_image_path}")


# Example usage
input_image = "abstract-black-futuristic-background.jpg"  # Path to your input image
output_image = "output.jpg"  # Path where the output image will be saved
crop_image(input_image, output_image)
